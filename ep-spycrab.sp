#include <sourcemod>
#include <enterprise>
#include <sdktools>
#include <sdkhooks>
#include <tf2>
#include <tf2_stocks>
#include <morecolors>

#define PLUGIN_VERSION			"1.0.0"
#define SUICIDE_BLOCK_MAX		3

#define SOUND_COUNTDOWN_BEGIN	"vo/announcer_am_roundstart03.mp3"

new g_iWinner = 0;

new g_iCountdown = 0;
new Handle:g_hCountdownTimer = INVALID_HANDLE;
new Handle:g_hGraceTimer = INVALID_HANDLE;

new bool:g_bGrace = false;
new g_iTaunt[MAXPLAYERS+1] = {0, ...};
// 0 = No taunt.
// 1 = Normal taunt.
// 2 = Spycrab taunt.

new g_iClientSlot[MAXPLAYERS+1] = {0, ...};
new g_iSlotClient[32+1] = {0, ...};

// -- Settings: --
new Float:g_flGraceTime = 5.0;

public Plugin:myinfo = 
{
	name = "Enterprise - Spycrab",
	author = PLUGIN_AUTHOR,
	description = "The Spycrab event manager plugin.",
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
};

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	CreateNative("ParseSpycrabConfiguration", Native_ParseSpycrabConfiguration);
}

public OnPluginStart()
{
	if(IsServerProcessing()) {
		OnEntitiesInitialized();
	}
	
	RegConsoleCmd("sm_countdown", Command_Countdown);
}

public Native_ParseSpycrabConfiguration(Handle:plugin, numParams)
{
	decl String:strPath[PLATFORM_MAX_PATH], String:strConfiguration[PLATFORM_MAX_PATH];
	GetNativeString(1, strConfiguration, sizeof(strConfiguration));
	
	BuildPath(Path_SM, strPath, sizeof(strPath), "configs/enterprise/configuration_spycrab.cfg");
	if(!FileExists(strPath)) {
		PrintToChatAll("Debug: nope");
		return 1;
	}
	
	PrintToChatAll("Debug: reading..");
	
	new Handle:kv = CreateKeyValues("Configuration");
	if(FileToKeyValues(kv, strPath) && KvJumpToKey(kv, strConfiguration, false))
	{
		PrintToChatAll("Debug: read");
		g_flGraceTime = KvGetFloat(kv, "gracetime", 12.0);
	} else {
		if(kv != INVALID_HANDLE) CloseHandle(kv);
		return 2;
	}
	if(kv != INVALID_HANDLE) CloseHandle(kv);
	return 0;
}

public OnMapStart()
{
	PrecacheSound("vo/announcer_begins_5sec.mp3");
	PrecacheSound("vo/announcer_begins_4sec.mp3");
	PrecacheSound("vo/announcer_begins_3sec.mp3");
	PrecacheSound("vo/announcer_begins_2sec.mp3");
	PrecacheSound("vo/announcer_begins_1sec.mp3");
	PrecacheSound(SOUND_COUNTDOWN_BEGIN);
}

public Action:Command_Countdown(client, args)
{
	g_iCountdown = 8;
	g_hCountdownTimer = CreateTimer(1.0, CountdownTimer, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Handled;
}

public OnEntitiesInitialized()
{
	new String:strTrigger[64];
	new entity = -1;
	
	HookSingleEntityOutput(FindSingleEntity("trigger_multiple", "spycrab_join_trigger"), "OnStartTouch", OnSpycrabTouch, false);
	
	for(new i=1; i <= 32; i++)
	{
		Format(strTrigger, sizeof(strTrigger), "spycrab_trigger%d", i);
		
		entity = FindSingleEntity("trigger_multiple", strTrigger);
		HookSingleEntityOutput(entity, "OnStartTouch", OnTriggerTouch, false);
		HookSingleEntityOutput(entity, "OnEndTouch", OnTriggerTouch, false);
	}
}

public OnEntityCreated(entity, const String:strClassname[])
{
	if(GetEventStatus(EVENT_SPYCRAB) == EVENT_STATUS_ACTIVE && g_bGrace)
	{
		if(StrEqual(strClassname, "instanced_scripted_scene", false)) {
			SDKHook(entity, SDKHook_Spawn, OnSceneSpawned);
		}
	}
}

public OnClientEventChanged(client, Event:event, Event:oldevent)
{
	if(IsValidClient(client))
	{
		if(event == EVENT_SPYCRAB)
		{
			//SDKHook(client, SDKHook_OnTakeDamage, OnPlayerDamaged);
			
			TeleportToSpycrab(client);		
			//g_iSuicideCount[client] = SUICIDE_BLOCK_MAX;
			
			CPrintToChatAll("{lawngreen}[SPYCRAB]{default} Player %s%N{default} is now participating.",  GetClientTeam(client) == 2 ? "{red}" : "{blue}", client);
		}
	/* 	else if(oldevent == EVENT_SPYCRAB) {
		} */
	}
}

public OnEventStatusChanged(Event:event, EventStatus:status)
{
	if(event == EVENT_SPYCRAB)
	{
		if(status == EVENT_STATUS_INACTIVE) {
			FireEntityInput("spycrab_join_trigger", "Disable");
			FireEntityInput("spycrab_join_prop", "Skin", "0");
			FireEntityInput("spycrab_join_particle", "Stop");
			FireEntityInput("spycrab_wall", "Disable");
			
			for(new i=1; i <= MaxClients; i++)
			{
				if(IsValidClient(i))
				{
					if(GetClientEvent(i) == EVENT_SPYCRAB) {
						SetClientEvent(i, EVENT_NONE);
						if(IsPlayerAlive(i)) TF2_RespawnPlayer(i);
					}
				}
			}
		}
		else if(status == EVENT_STATUS_SETUP) {
			FireEntityInput("spycrab_join_trigger", "Enable");
			FireEntityInput("spycrab_join_prop", "Skin", "1");
			FireEntityInput("spycrab_join_particle", "Start");
			FireEntityInput("spycrab_wall", "Disable");
		}
		else if(status == EVENT_STATUS_ACTIVE) {
			FireEntityInput("spycrab_join_trigger", "Disable");
			FireEntityInput("spycrab_join_prop", "Skin", "0");
			FireEntityInput("spycrab_join_particle", "Stop");
			FireEntityInput("spycrab_wall", "Enable");
			
			for(new i=1; i <= MaxClients; i++)
			{
				if(IsValidClient(i))
				{
					if(GetClientEvent(i) == EVENT_SPYCRAB)
					{
						new slot = g_iClientSlot[i];
						new String:strTrigger[64], Float:vecOrigin[3];
						new entity = -1;
						
						if(slot == 0) // For those that didn't choose a slot in time.
						{
							slot = GetRandomInt(1, 32);
							while(g_iSlotClient[slot] != 0) {
								slot = GetRandomInt(1, 32);
							}
							CPrintToChat(i, "{lawngreen}[SPYCRAB]{default} Randomly choosing slot...");
						}
						
						Format(strTrigger, sizeof(strTrigger), "spycrab_trigger%d", slot);
						entity = FindSingleEntity("trigger_multiple", strTrigger);
						
						GetEntPropVector(entity, Prop_Data, "m_vecOrigin", vecOrigin);
						vecOrigin[2] += -50.0;
						
						TeleportEntity(i, vecOrigin, NULL_VECTOR, NULL_VECTOR);
					}
				}
			}
		}
	}
}

public Action:OnSceneSpawned(entity)
{
	new client = GetEntPropEnt(entity, Prop_Data, "m_hOwner");
	if(g_iTaunt[client] == 0)
	{
		new String:strScene[PLATFORM_MAX_PATH];
		
		GetEntPropString(entity, Prop_Data, "m_iszSceneFile", strScene, sizeof(strScene));
		if(StrEqual(strScene, "scenes/player/spy/low/taunt05.vcd", false)) // Spycrab
		{
			g_iTaunt[client] = 2;
			TF2_IgnitePlayer(client, client);
			PrintToChatAll("fired 2");
		}
		else if(StrContains(strScene, "scenes/player/spy/low/taunt04", false) != -1)
		{
			g_iTaunt[client] = 1;
			PrintToChatAll("fired 1");
		}
		PrintToChatAll(strScene);
	}
}  

public OnSpycrabTouch(const String:strOutput[], entity, activator, Float:flDelay)
{
	if(IsValidClient(activator)) {
		CreateParticipantMenu(activator, EVENT_SPYCRAB);
	}
}

public OnTriggerTouch(const String:strOutput[], entity, activator, Float:flDelay)
{
	if(IsValidClient(activator))
	{
		new client = activator;
		
		new String:strEntity[64];
		GetEntPropString(entity, Prop_Data, "m_iName", strEntity, sizeof(strEntity));
		ReplaceString(strEntity, sizeof(strEntity), "spycrab_trigger", "", false);
		
		new index = StringToInt(strEntity);
		new slotclient = g_iSlotClient[index];
		if(slotclient == 0 || client == slotclient) 
		{
			if(StrEqual(strOutput, "OnStartTouch", false)) {
				g_iClientSlot[client] = index;
				g_iSlotClient[index] = client;
				
				CPrintToChat(client, "{lawngreen}[SPYCRAB]{default} You have entered slot {green}#%d{default}.", index);
			} else {
				g_iClientSlot[client] = 0;
				g_iSlotClient[index] = 0;
				
				CPrintToChat(client, "{lawngreen}[SPYCRAB]{default} You have left slot {green}#%d{default}.", index);
			}
		} 
		else if(client != slotclient)
		{
			CPrintToChat(client, "{lawngreen}[SPYCRAB]{default} Slot {green}#%d{default} is already occupied by %s%N{default}.", index, GetClientTeam(slotclient) == 2 ? "{red}" : "{blue}", slotclient);
		}
	}
}

public Action:CountdownTimer(Handle:timer)
{
	g_iCountdown--;
	
	if(g_iCountdown <= 5 && g_iCountdown >= 1) {
		new String:strSound[PLATFORM_MAX_PATH];
		Format(strSound, sizeof(strSound), "vo/announcer_begins_%dsec.mp3", g_iCountdown);
		
		EmitSoundToAll(strSound);
	}
	else if(g_iCountdown <= 0)
	{
		for(new i=1; i <= MaxClients; i++) {
			g_iTaunt[i] = 0;
		}
	
		g_bGrace = true;
		g_hGraceTimer = CreateTimer(g_flGraceTime, GraceTimer);
		EmitSoundToAll(SOUND_COUNTDOWN_BEGIN);
		
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

public Action:GraceTimer(Handle:timer)
{
	g_bGrace = false;
	g_hGraceTimer = INVALID_HANDLE;
	
	new iCount = 0;
	new bool:bRemaining[MAXPLAYERS+1] = {false, ...};
	
	for(new i=1; i <= MaxClients; i++)
	{
		if(IsValidClient(i))
		{
			if(GetClientEvent(i) == EVENT_SPYCRAB)
			{
				if(g_iTaunt[i] == 0) {
					SetClientEvent(i, EVENT_NONE);
					CPrintToChatAll("{lawngreen}[SPYCRAB]{default} Disqualified %s%N{default}. (Reason: Failure to Taunt)",  GetClientTeam(i) == 2 ? "{red}" : "{blue}", i);
				}
				else if(g_iTaunt[i] == 2) {
					SetClientEvent(i, EVENT_NONE);
					if(IsPlayerAlive(i)) TF2_RespawnPlayer(i);
					
					CPrintToChatAll("{lawngreen}[SPYCRAB]{default} Disqualified %s%N{default}. (Reason: Spycrabbed)",  GetClientTeam(i) == 2 ? "{red}" : "{blue}", i);
				} else {
					iCount++;
					bRemaining[i] = true;
				}
			}
		}
	}
	
	if(iCount == 0) {
		SetEventStatus(EVENT_SPYCRAB, EVENT_STATUS_INACTIVE);
		CPrintToChatAll("{lawngreen}[SPYCRAB]{default} All players have been disqualified, there are no winners.");
		CPrintToChatAll("{lawngreen}[SPYCRAB]{default} Thank you for playing!");
	}
	else if(iCount == 1) {
		for(new i=1; i <= MaxClients; i++){
			if(bRemaining[i]) {
				g_iWinner = i;
				break;
			}
		}
		
		SetEventStatus(EVENT_SPYCRAB, EVENT_STATUS_INACTIVE);
		CPrintToChatAll("{lawngreen}[SPYCRAB]{default} Player %s%N{default} won the Spycrab event!",  GetClientTeam(g_iWinner) == 2 ? "{red}" : "{blue}", g_iWinner);
		CPrintToChatAll("{lawngreen}[SPYCRAB]{default} Thank you for playing!");
	}
	
	return Plugin_Stop;
}

TeleportToSpycrab(any:client)
{
	new Float:vecOrigin[3];
	
	vecOrigin[0] = GetRandomFloat(2208.0, 3560.0);
	vecOrigin[1] = -1144.0;
	switch(GetRandomInt(1, 2))
	{
		case 1: vecOrigin[2] = 4.0;
		case 2: vecOrigin[2] = 180.0;
	}
	
	TeleportEntity(client, vecOrigin, NULL_VECTOR, NULL_VECTOR);
}

