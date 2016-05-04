#include <sourcemod>
#include <sdktools>
#include <enterprise>
#include <steamtools>
#include <cURL>

#define PLUGIN_VERSION							"1.0.0"
#define GROUP_ID								9614776
#define LOOP_TIMEOUT							16
#define GROUP_COUNT_UPDATE_INTERVAL				60.0
#define GROUP_MEMBERSHIP_UPDATE_INTERVAL		5.0

#define SOUND_EVENT_REQUEST		"ui/duel_challenge.wav"
#define SOUND_EVENT_JOIN		"ui/duel_challenge_accepted.wav"
#define SOUND_EVENT_LEAVE		"ui/duel_challenge_rejected.wav"

#define SOUND_ANNOUNCER_BEGIN_60	"vo/announcer_begins_60sec.mp3"
#define SOUND_ANNOUNCER_BEGIN_30	"vo/announcer_begins_30sec.mp3"
#define SOUND_ANNOUNCER_BEGIN_20	"vo/announcer_begins_20sec.mp3"
#define SOUND_ANNOUNCER_BEGIN_10	"vo/announcer_begins_10sec.mp3"
#define SOUND_ANNOUNCER_BEGIN_5		"vo/announcer_begins_5sec.mp3"
#define SOUND_ANNOUNCER_BEGIN_4		"vo/announcer_begins_4sec.mp3"
#define SOUND_ANNOUNCER_BEGIN_3		"vo/announcer_begins_3sec.mp3"
#define SOUND_ANNOUNCER_BEGIN_2		"vo/announcer_begins_2sec.mp3"
#define SOUND_ANNOUNCER_BEGIN_1		"vo/announcer_begins_1sec.mp3"
#define SOUND_ANNOUNCER_BEGIN		"vo/announcer_am_roundstart03.mp3"

new gCollisionGroup = -1;
new gMemberCount = 0;
new gMembership[MAXPLAYERS+1] = {-1, ...};

// Forwards:
new Handle:g_hEntitiesInitialized = INVALID_HANDLE;
new Handle:g_hEventStatusChanged = INVALID_HANDLE;
new Handle:g_hClientEventChanged = INVALID_HANDLE;

new Handle:gConVar[10] = INVALID_HANDLE;
new bool:gFoundData = false;

new EventStatus:g_eEvent[MAXEVENTS+1] = {EVENT_STATUS_ACTIVE, ...};
new Event:g_eClientEvent[MAXPLAYERS+1] = {EVENT_NONE, ...};
new Event:g_eTempEvent[MAXPLAYERS+1] = {EVENT_NONE, ...};

new g_iSetupTime[MAXEVENTS+1] = {0, ...};
new g_iCountdown[MAXEVENTS+1] = {0, ...};
new g_iMaxParticipants[MAXEVENTS+1] = {-1, ...};
new Handle:g_hEventTimer[MAXEVENTS+1] = {INVALID_HANDLE, ...};
new Handle:hHudEvent[MAXEVENTS+1] = {INVALID_HANDLE, ...};

new g_iEventColour[MAXEVENTS+1][3] = {
	{255, 255, 255}, // error
	{255, 0, 0}, // Arena
	{0, 255, 0}, // Quiz
	{0, 0, 255}, // 
	{255, 128, 0},
	{255, 255, 0},
	{255, 255, 255},
	{255, 255, 255},
	{255, 255, 255},
	{255, 255, 255},
	{255, 255, 255}
};

public Plugin:myinfo = 
{
	name = "Enterprise - Core",
	author = "SoulSharD",
	description = "The core plugin for handling natives/functions for related map plugins.",
	version = PLUGIN_VERSION,
	url = ""
};

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	// Natives:
	
	CreateNative("IsValidClient", Native_IsValidClient);
	CreateNative("GetPlayerCount", Native_GetPlayerCount);
	CreateNative("RandomChance", Native_RandomChance);
	CreateNative("FireEntityInput", Native_FireEntityInput);
	CreateNative("FindSingleEntity", Native_FindSingleEntity);
	CreateNative("DisplayAnnotation", Native_DisplayAnnotation);
	CreateNative("SetTextureIndex", Native_SetTextureIndex);
	CreateNative("SubmitToLog", Native_SubmitToLog);
	CreateNative("CreateParticle", Native_CreateParticle);
	CreateNative("GetGroupMemberCount", Native_GetGroupMemberCount);
	CreateNative("GetClientGroupMembership", Native_GetClientGroupMembership);
	CreateNative("AddEntityOutput", Native_AddEntityOutput);
	CreateNative("GetDistanceFromGround", Native_GetDistanceFromGround);
	CreateNative("DeleteEdict", Native_DeleteEdict);
	CreateNative("CreateParticipantMenu", Native_CreateParticipantMenu);
	CreateNative("AnnouncerCountdown", Native_AnnouncerCountdown);
	
	CreateNative("SetEventStatus", Native_SetEventStatus);
	CreateNative("GetEventStatus", Native_GetEventStatus);
	CreateNative("SetClientEvent", Native_SetClientEvent);
	CreateNative("GetClientEvent", Native_GetClientEvent);
	CreateNative("GetEventPlayerCount", Native_GetEventPlayerCount);
	CreateNative("InitiateEventSetup", Native_InitiateEventSetup);
	
	// Forwards:
	g_hEntitiesInitialized = CreateGlobalForward("OnEntitiesInitialized", ET_Ignore);
	if(g_hEntitiesInitialized == INVALID_HANDLE) {
		SubmitToLog(LOG_ERROR, "Unable to create global forward OnEntitiesInitialized().");
	}
	
	g_hEventStatusChanged = CreateGlobalForward("OnEventStatusChanged", ET_Ignore, Param_Cell, Param_Cell);
	if(g_hEventStatusChanged == INVALID_HANDLE) {
		SubmitToLog(LOG_ERROR, "Unable to create global forward OnEventStatusChanged().");
	}
	
	g_hClientEventChanged = CreateGlobalForward("OnClientEventChanged", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
	if(g_hClientEventChanged == INVALID_HANDLE) {
		SubmitToLog(LOG_ERROR, "Unable to create global forward OnClientEventChanged().");
	}

	RegPluginLibrary("epcore");
	return APLRes_Success;
}

public OnPluginStart()
{
	CheckPlugin();
	
	if(IsServerProcessing()) {
		OnEntitiesInitialized();
	}

	gCollisionGroup = FindSendPropOffs("CBaseEntity", "m_CollisionGroup");
	if(gCollisionGroup == -1) // Seriously, if the server can't find this collision offset; it's broken.
	{
		SubmitToLog(LOG_WARNING, "Unable to find CBaseEntity::m_CollisionGroup. Player collision groups cannot be modified.");
	}
	
	gConVar[0] = CreateConVar("sm_collisiongroup", "17", "Sets the collision group for all players.");
	// Collision group 17 is awesome. Though enginneers can trap other people in their buildables.
	// And I'm sure some of our wonderful admins will find more exploits.
	
	//RegConsoleCmd("sm_leave", Command_Leave, "Allows players to leave an event they're currently in.");
	
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("teamplay_round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	
	UpdateGroupCount(INVALID_HANDLE);
	UpdateGroupMembership(INVALID_HANDLE);
	
	for(new i=1; i <= MAXEVENTS; i++) {
		hHudEvent[i] = CreateHudSynchronizer();
	}	
}

public OnMapStart()
{
	PrecacheSound(SOUND_EVENT_REQUEST);
	PrecacheSound(SOUND_EVENT_JOIN);
	PrecacheSound(SOUND_EVENT_LEAVE);
	
	PrecacheSound(SOUND_ANNOUNCER_BEGIN_60);
	PrecacheSound(SOUND_ANNOUNCER_BEGIN_30);
	PrecacheSound(SOUND_ANNOUNCER_BEGIN_20);
	PrecacheSound(SOUND_ANNOUNCER_BEGIN_10);
	PrecacheSound(SOUND_ANNOUNCER_BEGIN_5);
	PrecacheSound(SOUND_ANNOUNCER_BEGIN_4);
	PrecacheSound(SOUND_ANNOUNCER_BEGIN_3);
	PrecacheSound(SOUND_ANNOUNCER_BEGIN_2);
	PrecacheSound(SOUND_ANNOUNCER_BEGIN_1);
	PrecacheSound(SOUND_ANNOUNCER_BEGIN);
}

public OnClientDisconnect(client)
{
	g_eClientEvent[client] = EVENT_NONE;
}

public Action:Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(gCollisionGroup != -1) {
		SetEntData(client, gCollisionGroup, GetConVarInt(gConVar[0]), 4, true);
	}
}

public Action:Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	InitializeEntities();
	return Plugin_Continue;
}

public TF2_OnWaitingForPlayersStart()
{
	ServerCommand("mp_waitingforplayers_cancel 1");
	InitializeEntities();
}

/* public TF2_OnWaitingForPlayersEnd()
{
	InitializeEntities();
} */

InitializeEntities()
{
	Call_StartForward(g_hEntitiesInitialized);
	if(Call_Finish() != SP_ERROR_NONE) {
		SubmitToLog(LOG_ERROR, "Unable to call forward OnEntitiesInitialized().");
	}
}

public OnEntitiesInitialized()
{
	for(new i=1; i <= MAXEVENTS; i++) {
		SetEventStatus(Event:i, EVENT_STATUS_INACTIVE);
	}
}

public OnEventStatusChanged(Event:event, EventStatus:status)
{
	new iEvent = _:event;
	
	new String:strSprite[64];
	new String:strBrush[64];
	new String:strColour[][] = {
		"175 0 0", // Inactive
		"255 128 0", // Setup
		"0 255 0" // Active
	};
	
	Format(strSprite, sizeof(strSprite), "event_sprite%d", iEvent)
	Format(strBrush, sizeof(strBrush), "event_brush%d", iEvent);
	
	FireEntityInput(strSprite, "Color", strColour[status]);
	FireEntityInput(strBrush, "Color", strColour[status]);
	
	new EventStatus:statusCount[3];
	for(new i=1; i <= MAXEVENTS; i++) {
		statusCount[GetEventStatus(i)]++;
	}
	
	if(statusCount[EVENT_STATUS_SETUP] > 0) {
		FireEntityInput("event_sprite", "Color", strColour[EVENT_STATUS_SETUP]);
		FireEntityInput("event_brush", "Color", strColour[EVENT_STATUS_SETUP]);
	}
	else if(statusCount[EVENT_STATUS_ACTIVE] > 0) {
		FireEntityInput("event_sprite", "Color", strColour[EVENT_STATUS_ACTIVE]);
		FireEntityInput("event_brush", "Color", strColour[EVENT_STATUS_ACTIVE]);
	} else {
		FireEntityInput("event_sprite", "Color", strColour[EVENT_STATUS_INACTIVE]);
		FireEntityInput("event_brush", "Color", strColour[EVENT_STATUS_INACTIVE]);
	}
}

public OnClientEventChanged(client, Event:event, Event:oldevent)
{
	if(IsValidClient(client))
	{
		if(event != EVENT_NONE) {
			EmitSoundToClient(client, SOUND_EVENT_JOIN);
		} else {
			EmitSoundToClient(client, SOUND_EVENT_LEAVE);
		}
	}
	
	if(GetEventStatus(event) == EVENT_STATUS_SETUP) {
		if(GetEventPlayerCount(event) == g_iMaxParticipants[event])
		{
			g_iMaxParticipants[event] = -1;
			SetEventStatus(event, EVENT_STATUS_ACTIVE);
			if(g_hEventTimer[event] != INVALID_HANDLE)
			{
				KillTimer(g_hEventTimer[event]);
				g_hEventTimer[event] = INVALID_HANDLE;
			}
		}
	}
}

public OnClientPostAdminCheck(client)
{
	if(!Steam_RequestGroupStatus(client, GROUP_ID)) {
		gMembership[client] = -1;
		SubmitToLog(LOG_ERROR, "Unable to request client %d's group status.", client);
	}
}

public Action:UpdateGroupCount(Handle:timer)
{
	new Handle:hCURL = curl_easy_init();
	if(hCURL != INVALID_HANDLE)
	{
		curl_easy_setopt_function(hCURL, CURLOPT_WRITEFUNCTION, OnCURLFoundData);
		curl_easy_setopt_int(hCURL, CURLOPT_FAILONERROR, true);
		curl_easy_setopt_string(hCURL, CURLOPT_URL, "http://steamcommunity.com/gid/103582791431459640/memberslistxml/?xml=1");
		curl_easy_perform_thread(hCURL, OnCURLFinished);
	}
	CreateTimer(GROUP_COUNT_UPDATE_INTERVAL, UpdateGroupCount);
	return Plugin_Continue;
}

public Action:UpdateGroupMembership(Handle:timer)
{
	for(new i=1; i <= MaxClients; i++)
	{
		if(IsValidClient(i))
		{
			if(!Steam_RequestGroupStatus(i, GROUP_ID)) {
				gMembership[i] = -1;
			}
		}
	}
	CreateTimer(GROUP_MEMBERSHIP_UPDATE_INTERVAL, UpdateGroupMembership);
	return Plugin_Continue;
}

public Steam_GroupStatusResult(client, groupAccountID, bool:groupMember, bool:groupOfficer)
{
	if(groupAccountID == GROUP_ID) {
		gMembership[client] = groupMember + groupOfficer;
	} else {
		gMembership[client] = -1;
	}
}

public OnCURLFoundData(Handle:hndl, const String:buffer[], const bytes, const nmemb)
{
	if(!gFoundData)
	{
		new maxlength = nmemb + 13;
		new String:data[maxlength];
		StrCat(data, maxlength, buffer);
		
		new iPosition;
		iPosition = StrContains(data, "<memberCount>", true);
		if(iPosition != -1)
		{
			new String:strBuffer[128];
			ReplaceString(data, maxlength, "<memberCount>", "", false);
			strcopy(strBuffer, sizeof(strBuffer), data[iPosition]);
			
			iPosition = StrContains(strBuffer, "</memberCount>", false);
			ReplaceString(strBuffer, sizeof(strBuffer), strBuffer[iPosition], "");
			
			gMemberCount = StringToInt(strBuffer);
			gFoundData = true;
		}
	}
	return bytes * nmemb;
}

public OnCURLFinished(Handle:curl, CURLcode:code)
{
	if(!gFoundData)	{
		SubmitToLog(LOG_WARNING, "Unable to retrieve group member count. (CURL Error: %d)", code);
	}
}

public Native_IsValidClient(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	if (client <= 0 || client > MaxClients) return false;
	if (!IsClientInGame(client)) return false;
	if (IsFakeClient(client)) return false;
	if (IsClientSourceTV(client) || IsClientReplay(client)) return false;
	return true;
}

public Native_GetPlayerCount(Handle:plugin, numParams)
{
	new x = 0;
	for(new i=1; i <= MaxClients; i++)
	{
		if((GetNativeCell(1) ? IsClientInGame(i) : IsClientConnected(i)) && !IsFakeClient(i)) {
			x++;
		} 
	}
	return x;
}

public Native_RandomChance(Handle:plugin, numParams)
{
	new Float:flChance = GetNativeCell(1);
	if(GetRandomFloat(0.0, 1.0) <= flChance) {
		return true;
	}
	return false;
}

// I'm proud of this.
public Native_FireEntityInput(Handle:plugin, numParams)
{
	decl String:strTargetname[128], String:strInput[32], String:strParameter[64];
	new Float:flDelay;

	GetNativeString(1, strTargetname, sizeof(strTargetname));
	GetNativeString(2, strInput, sizeof(strInput));
	GetNativeString(3, strParameter, sizeof(strParameter));
	flDelay = GetNativeCell(4);

	decl String:strBuffer[255];
	Format(strBuffer, sizeof(strBuffer), "OnUser1 %s:%s:%s:%f:1", strTargetname, strInput, strParameter, flDelay);
	
	new entity = CreateEntityByName("info_target"); // Dummy entity. 
	if(IsValidEdict(entity))
	{
		DispatchSpawn(entity);
	
		SetVariantString(strBuffer);
		AcceptEntityInput(entity, "AddOutput");
		AcceptEntityInput(entity, "FireUser1");
		
		DeleteEdict(entity, 0.0); // Remove on next frame.
		return true;
	}
	return false;
}

public Native_FindSingleEntity(Handle:plugin, numParams)
{
	decl String:strClassname[128], String:strTargetname[128];
	GetNativeString(1, strClassname, sizeof(strClassname));
	GetNativeString(2, strTargetname, sizeof(strTargetname));

	new entity = -1, String:strEntity[128];
	while((entity = FindEntityByClassname(entity, strClassname)) != -1)
	{
		GetEntPropString(entity, Prop_Data, "m_iName", strEntity, sizeof(strEntity));
		if(StrEqual(strEntity, strTargetname, false)) {
			return entity;
		}
	}
	return -1;
}

// Special thanks to Geit.
// I would've just created that 'training_annotation' entity. But this way is much easier.
public Native_DisplayAnnotation(Handle:plugin, numParams)
{
	static id=0;
	new Handle:event = CreateEvent("show_annotation");
	if(event != INVALID_HANDLE) 
	{
		id++;
		new client = GetNativeCell(1);
		new Float:vecOrigin[3], String:strText[255], Float:flLifetime;
		
		GetNativeArray(2, vecOrigin, 3);
		GetNativeString(3, strText, sizeof(strText));
		flLifetime = GetNativeCell(4);
		
		SetEventFloat(event, "worldPosX", vecOrigin[0]);
		SetEventFloat(event, "worldPosY", vecOrigin[1]);
		SetEventFloat(event, "worldPosZ", vecOrigin[2]);
		SetEventFloat(event, "lifetime", flLifetime);
		SetEventInt(event, "id", id);
		SetEventString(event, "text", strText);
		SetEventString(event, "play_sound", "vo/null.mp3"); // TODO: fix the annoying error message
		SetEventInt(event, "visibilityBitfield", (1 << client));
		FireEvent(event);
		
		return true;
	}
	return false;
}

public Native_SubmitToLog(Handle:plugin, numParams)
{
	decl String:strPath[PLATFORM_MAX_PATH];
	decl const String:strType[][] = {
		"general",
		"warning",
		"error"
	}
	
	BuildPath(Path_SM, strPath, sizeof(strPath), "logs/enterprise/%s.txt", strType[GetNativeCell(1)]);
	new Handle:hFile = OpenFile(strPath, "a");
	if(hFile != INVALID_HANDLE)
	{
		decl String:strPlugin[32], 
			String:strBuffer[255], 
			String:strTime[64];
			
		GetPluginFilename(plugin, strPlugin, sizeof(strPlugin)); // The 'plugin' handle should be the plugin that called the native.
		GetNativeString(2, strBuffer, sizeof(strBuffer));
		FormatNativeString(0, 2, 3, sizeof(strBuffer), _, strBuffer);
		FormatTime(strTime, sizeof(strTime), "%d/%m/%Y | %H:%M:%S", GetTime());
		
		if(!WriteFileLine(hFile, "[%s] - (%s) =: %s", strTime, strPlugin, strBuffer)) {
			LogError("[SM] Unable to append log entry.");
			CloseHandle(hFile);
			return false;
		}
		CloseHandle(hFile);
		return true;
	} else {
		LogError("[SM] Unable to create logging file: 'logs/enterprise/%s.txt'.", strType[GetNativeCell(1)]);
	}
	CloseHandle(hFile);
	return false;
}

public Native_CreateParticle(Handle:plugin, numParams)
{
	new entity = CreateEntityByName("info_particle_system");
	if(IsValidEdict(entity))
	{
		new Float:vecOrigin[3], String:strParticle[64],
			Float:flDelay = GetNativeCell(3),
			Float:flLifetime = GetNativeCell(4);
		
		GetNativeString(2, strParticle, sizeof(strParticle));
		DispatchKeyValue(entity, "effect_name", strParticle); 
		
		DispatchSpawn(entity);
		ActivateEntity(entity); // Required for particles.
		
		AddEntityOutput(entity, "OnUser1 !self:Start::%f:1", flDelay);
		AddEntityOutput(entity, "OnUser1 !self:Kill::%f:1", flDelay + flLifetime);
		AcceptEntityInput(entity, "FireUser1");
		
		GetNativeArray(1, vecOrigin, 3);
		TeleportEntity(entity, vecOrigin, NULL_VECTOR, NULL_VECTOR);
		
		return entity;
	}
	return -1;
}

public Native_SetTextureIndex(Handle:plugin, numParams)
{
	new entity = CreateEntityByName("env_texturetoggle");
	if(IsValidEdict(entity))
	{
		decl String:strBrush[64];
		GetNativeString(1, strBrush, sizeof(strBrush));
		
		DispatchKeyValue(entity, "target", strBrush);
		
		AddEntityOutput(entity, "OnUser1 !self:SetTextureIndex:%d::1", GetNativeCell(2));
		AddEntityOutput(entity, "OnUser1 !self:Kill:::1");
		AcceptEntityInput(entity, "FireUser1");
		
		return true;
	}
	return false;
}

public Native_GetGroupMemberCount(Handle:plugin, numParams) {
	return gMemberCount;
}

public Native_GetClientGroupMembership(Handle:plugin, numParams) {
	return gMembership[GetNativeCell(1)];
}

public Native_AddEntityOutput(Handle:plugin, numParams)
{
	decl String:strBuffer[256];
	GetNativeString(2, strBuffer, sizeof(strBuffer));
	FormatNativeString(0, 2, 3, sizeof(strBuffer), _, strBuffer);

	SetVariantString(strBuffer);
	AcceptEntityInput(GetNativeCell(1), "AddOutput");
}

public Native_GetDistanceFromGround(Handle:plugin, numParams)
{
	new Float:vecOrigin[3], Float:flGround[3];
	GetNativeArray(1, vecOrigin, 3);
    
	TR_TraceRayFilter(vecOrigin, Float:{90.0,0.0,0.0}, MASK_PLAYERSOLID, RayType_Infinite, TraceRayNoPlayers);
	if(TR_DidHit())
	{
		TR_GetEndPosition(flGround);
		return _:GetVectorDistance(vecOrigin, flGround);
	}
	return _:0.0;
}

public bool:TraceRayNoPlayers(entity, mask)
{
	if((entity >= 1 && entity <= MaxClients)) {
		return false;
	}
	return true;
} 

public Native_DeleteEdict(Handle:plugin, numParams)
{
	new entity = GetNativeCell(1);
	new Float:flDelay = GetNativeCell(2);
	
	if(entity <= 2048) entity = EntIndexToEntRef(entity); 
	if(flDelay < 0.1) RequestFrame(DeleteNextFrame, entity);
	else CreateTimer(flDelay, DeleteDelay, entity, TIMER_FLAG_NO_MAPCHANGE);
}

public DeleteNextFrame(any:ref)
{
	new entity = EntRefToEntIndex(ref);
	if(entity != INVALID_ENT_REFERENCE) {
		AcceptEntityInput(entity, "Kill");
	}
}

public Action:DeleteDelay(Handle:timer, any:ref)
{
	new entity = EntRefToEntIndex(ref);
	if(entity != INVALID_ENT_REFERENCE) {
		AcceptEntityInput(entity, "Kill");
	}
	return Plugin_Stop;
}

public Native_SetEventStatus(Handle:plugin, numParams)
{
	new Event:event = GetNativeCell(1);
	new EventStatus:status = GetNativeCell(2);
	
	if(g_eEvent[event] != status)
	{
		g_eEvent[event] = status;
		
		Call_StartForward(g_hEventStatusChanged);
		Call_PushCell(event);
		Call_PushCell(status);
		if(Call_Finish() != SP_ERROR_NONE) {
			SubmitToLog(LOG_ERROR, "Unable to call forward OnEventStatusChanged().");
		}
	}
}

public Native_CreateParticipantMenu(Handle:plugin, numParams)
{
	new Handle:panel = CreatePanel(INVALID_HANDLE);
	if(panel != INVALID_HANDLE)
	{
		new String:strText[128];		
		new client = GetNativeCell(1);
		new Event:event = GetNativeCell(2);
		g_eTempEvent[client] = event;
		
		Format(strText, sizeof(strText), "[Enterprise] %s Participation:", g_strEvent[event]);
		SetPanelTitle(panel, strText);

		DrawPanelItem(panel, "", ITEMDRAW_SPACER|ITEMDRAW_RAWLINE);
		DrawPanelText(panel, "ALL EVENTS ARE FREE");
		DrawPanelItem(panel, "", ITEMDRAW_SPACER|ITEMDRAW_RAWLINE);
		DrawPanelText(panel, "By choosing accept you will become a participant in this event.");
		DrawPanelText(panel, "Remember, events are about enjoyment with the possibility");
		DrawPanelText(panel, "of winning prizes. Particpation is free, you will lose nothing.");
		DrawPanelItem(panel, "", ITEMDRAW_SPACER|ITEMDRAW_RAWLINE);
		Format(strText, sizeof(strText), "Please select 'Accept' to join the %s event.", g_strEvent[event]);
		DrawPanelText(panel, strText);
		DrawPanelItem(panel, "", ITEMDRAW_SPACER|ITEMDRAW_RAWLINE);
		DrawPanelItem(panel, "Accept");
		DrawPanelItem(panel, "Decline");
		
		SendPanelToClient(panel, client, ParticipationCallback, MENU_TIME_FOREVER);
		EmitSoundToClient(client, SOUND_EVENT_REQUEST);
		
		CloseHandle(panel);
		return true;
	}
	return false;
}

public ParticipationCallback(Handle:menu, MenuAction:action, client, param)
{
	if(action == MenuAction_Select)
	{
		if(param == 1)
		{
			SetClientEvent(client, g_eTempEvent[client]);
		} else {
			EmitSoundToClient(client, SOUND_EVENT_LEAVE);
		}
	}
}

public Native_AnnouncerCountdown(Handle:plugin, numParams)
{
	new Event:event = GetNativeCell(2);
	g_iCountdown[event] = GetNativeCell(1);
	CreateTimer(1.0, CountdownTimer, event, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public Action:CountdownTimer(Handle:timer, Event:event)
{
	decl String:strSound[PLATFORM_MAX_PATH];
	
	switch(g_iCountdown[event])
	{
		case 60: strSound = SOUND_ANNOUNCER_BEGIN_60;
		case 30: strSound = SOUND_ANNOUNCER_BEGIN_30;
		case 20: strSound = SOUND_ANNOUNCER_BEGIN_20;
		case 10: strSound = SOUND_ANNOUNCER_BEGIN_10;
		case 5: strSound = SOUND_ANNOUNCER_BEGIN_5;
		case 4: strSound = SOUND_ANNOUNCER_BEGIN_4;
		case 3: strSound = SOUND_ANNOUNCER_BEGIN_3;
		case 2: strSound = SOUND_ANNOUNCER_BEGIN_2;
		case 1: strSound = SOUND_ANNOUNCER_BEGIN_1;
		case 0: strSound = SOUND_ANNOUNCER_BEGIN;
		default: 
		{
			g_iCountdown[event]--;
			return Plugin_Continue;
		}
	}
	
	for(new i=1; i <= MaxClients; i++) 
	{
		if(IsValidClient(i))
		{
			if(GetClientEvent(i) == event) {
				EmitSoundToClient(i, strSound);
			}
		}
	}
	
	if(g_iCountdown[event] <= 0) {
		g_iCountdown[event] = 0;
		return Plugin_Stop;
	}

	g_iCountdown[event]--;
	return Plugin_Continue;
}

public Native_GetEventStatus(Handle:plugin, numParams) {
	return _:g_eEvent[GetNativeCell(1)];
}

public Native_SetClientEvent(Handle:plugin, numParams) {
	
	new client = GetNativeCell(1);
	new Event:event = GetNativeCell(2);
	new Event:oldevent = g_eClientEvent[client]
	
	if(oldevent != event)
	{
		g_eClientEvent[client] = event;
		
		Call_StartForward(g_hClientEventChanged);
		Call_PushCell(client);
		Call_PushCell(event);
		Call_PushCell(oldevent);
		if(Call_Finish() != SP_ERROR_NONE) {
			SubmitToLog(LOG_ERROR, "Unable to call forward OnClientEventChanged().");
		}
	}
}

public Native_GetClientEvent(Handle:plugin, numParams) {
	return _:g_eClientEvent[GetNativeCell(1)];
}

public Native_GetEventPlayerCount(Handle:plugin, numParams)
{
	new Event:event = GetNativeCell(1), x;
	for(new i=1; i <= MaxClients; i++)
	{
	//	if(IsValidClient(i))
		{
			if(GetClientEvent(i) == event) x++;
		}
	}
	return x;
}

public Native_InitiateEventSetup(Handle:plugin, numParams)
{
	new Event:event = GetNativeCell(1);
	new time = GetNativeCell(2);
	new minplayers = GetNativeCell(3);
	new maxplayers = GetNativeCell(4);
	
	if(GetPlayerCount(true) < minplayers)
	{
		PrintToChatAll("[SERVER] Unable to initiate %s event.", g_strEvent[event]);
		PrintToChatAll("Not enough players in server to meet minimum player requirement. (Minimum: %d)", minplayers);
		return false;
	}
	
	SetEventStatus(event, EVENT_STATUS_SETUP);
	
	if(time < 10 || time > 300) {
		time = DEFAULT_EVENT_TIME;
	}

	g_iSetupTime[event] = time;
	g_iMaxParticipants[event] = maxplayers;

	new Handle:data = CreateDataPack();
	
	if(g_hEventTimer[event] != INVALID_HANDLE) {
		KillTimer(g_hEventTimer[event]);
	}
	
	g_hEventTimer[event] = CreateDataTimer(1.0, OnEventTimer, data, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	WritePackCell(data, event);
	WritePackCell(data, minplayers);
	
	return true;
}

public Action:OnEventTimer(Handle:timer, Handle:data)
{
	ResetPack(data);
	
	new Event:event = ReadPackCell(data);
	new minplayers = ReadPackCell(data);
	new players = GetEventPlayerCount(event);
	
	decl String:strTime[64];
	FormatTime(strTime, sizeof(strTime), "%M:%S", g_iSetupTime[event]);
	
	new slot = 0;
	for(new i=1; i <= MAXEVENTS; i++)
	{
		if(g_hEventTimer[i] != INVALID_HANDLE) slot++;
		if(i == _:event) break;
	}
	
	SetHudTextParams(-1.0, 0.1 + (slot * 0.03), 1.15, g_iEventColour[event][0], g_iEventColour[event][1], g_iEventColour[event][2],  255, 2, 0.0, 0.0, 0.0);
	for(new i=1; i <= MaxClients; i++) {
		if(IsValidClient(i)) {
			ShowSyncHudText(i, hHudEvent[event], "%s - Setup: %s []", g_strEvent[event], strTime);
		}
	}
	
	if(g_iSetupTime[event]-- <= 0)
	{
		g_iMaxParticipants[event] = -1;
		if(players >= minplayers || players == g_iMaxParticipants[event]) { // The maxplayers check here should never happen, but it's here just in case.
			SetEventStatus(event, EVENT_STATUS_ACTIVE);
		} else {
			SetEventStatus(event, EVENT_STATUS_INACTIVE);
			PrintToChatAll("[SERVER] Unable to activate the %s event.", g_strEvent[event]);
			PrintToChatAll("[SERVER] Reason: Minimum player requirement was not met. (Minimum: %d)", minplayers);
		}
		g_hEventTimer[event] = INVALID_HANDLE;
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

CheckPlugin()
{
	decl String:strDir[64], String:strMap[64];
	
	GetGameFolderName(strDir, sizeof(strDir));
	if(strcmp(strDir, "tf") != 0) // Duh.
	{
		SubmitToLog(LOG_ERROR, "This plugin will only work for Team Fortress 2.");
		SetFailState("[ENTERPRISE] This plugin will only work for Team Fortress 2.");
	}
	
	GetCurrentMap(strMap, sizeof(strMap));
	if(!StrEqual(strMap, REQUIRED_MAP, true)) // Uh oh. Someone forgot to set the default map.
	{
		SubmitToLog(LOG_ERROR, "This map is not compatible with this plugin. (Current: '%s') (Required: '%s')", strMap, REQUIRED_MAP);
		SetFailState("[ENTERPRISE] Current map is not compatible.");
	}	
	// SetFailState doesn't return. Once fired: no further code will be executed.
}