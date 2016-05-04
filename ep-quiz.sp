#include <sourcemod>
#include <enterprise>
#include <sdktools>
#include <sdkhooks>
#include <tf2_stocks>
#include <morecolors>

#define PLUGIN_VERSION			"1.0.0"
#define SUICIDE_BLOCK_MAX		3

#define VECTOR_LOOK_POINT		Float:{0.0, -5398.0, 76.0}

#define SOUND_WARNING			"ui/rd_2base_alarm.wav"

new g_iSuicideCount[MAXPLAYERS+1] = {SUICIDE_BLOCK_MAX, ...};


public Plugin:myinfo = 
{
	name = "Enterprise - Quiz",
	author = PLUGIN_AUTHOR,
	description = "The Quiz event manager plugin.",
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
};

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	CreateNative("ParseQuizConfiguration", Native_ParseQuizConfiguration);
}

public OnPluginStart()
{
	if(IsServerProcessing()) {
		OnEntitiesInitialized();
	}

	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);

	AddCommandListener(Command_Suicide, "kill");
	AddCommandListener(Command_Suicide, "explode");
	AddCommandListener(Command_Suicide, "spectate");
	AddCommandListener(Command_Suicide, "jointeam");
	AddCommandListener(Command_Suicide, "joinclass");
	
	AddCommandListener(Command_Chat, "say");
	AddCommandListener(Command_Chat, "say_team");
}

public Native_ParseQuizConfiguration(Handle:plugin, numParams)
{
	decl String:strPath[PLATFORM_MAX_PATH], String:strConfiguration[PLATFORM_MAX_PATH];
	GetNativeString(1, strConfiguration, sizeof(strConfiguration));
	
	BuildPath(Path_SM, strPath, sizeof(strPath), "configs/configuration_quiz.cfg");
	if(!FileExists(strPath)) {
		return 1;
	}
	
	new Handle:kv = CreateKeyValues("Configuration");
	if(FileToKeyValues(kv, strPath) && KvJumpToKey(kv, strConfiguration, false))
	{
		PrintToChatAll("Successfully loaded: %s", strConfiguration);
	} else {
		if(kv != INVALID_HANDLE) CloseHandle(kv);
		return 2;
	}
	if(kv != INVALID_HANDLE) CloseHandle(kv);
	return 0;
}

public OnMapStart()
{
	PrecacheSound(SOUND_WARNING);
}

public OnEntitiesInitialized()
{
	new entity = -1;
	
	entity = FindSingleEntity("trigger_multiple", "quiz_join_trigger");
	HookSingleEntityOutput(entity, "OnStartTouch", OnQuizTouch, false);
	//HookSingleEntityOutput(entity, "OnEndTouch", OnQuizTouch, false);
}

public OnClientDisconnect(client)
{
	if(GetClientEvent(client) == EVENT_QUIZ && GetEventStatus(EVENT_QUIZ) == EVENT_STATUS_ACTIVE)
	{
		CPrintToChatAll("{lawngreen}[QUIZ]{default} Disqualified %s%N{default}. (Reason: Disconnect)",  GetClientTeam(client) == 2 ? "{red}" : "{blue}", client);
	}
}

public Action:Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(IsValidClient(client))
	{
		SDKHook(client, SDKHook_OnTakeDamage, OnPlayerDamaged);
		if(GetClientEvent(client) == EVENT_QUIZ) {
			TeleportToQuiz(client);
		}
	}
	return Plugin_Continue;
}

public Action:Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(IsValidClient(client))
	{
		SDKUnhook(client, SDKHook_OnTakeDamage, OnPlayerDamaged);
		if(GetClientEvent(client) == EVENT_QUIZ)
		{
			if(GetEventStatus(EVENT_QUIZ) == EVENT_STATUS_ACTIVE)
			{
				CPrintToChatAll("{lawngreen}[QUIZ]{default} Disqualified %s%N{default}. (Reason: Suicide)",  GetClientTeam(client) == 2 ? "{red}" : "{blue}", client);
				SetClientEvent(client, EVENT_NONE);
			}
			else if(GetEventStatus(EVENT_QUIZ) == EVENT_STATUS_SETUP)
			{
				RequestFrame(RespawnDelay, client);
				CPrintToChat(client, "{lawngreen}[QUIZ]{default} Event is currently setting up; respawned instantly.");
				CPrintToChat(client, "{lawngreen}[QUIZ]{default} If you wish to leave the event; type {gold}!leave{default}.");
			}
		}
	}
	return Plugin_Continue;
}

public Action:Command_Chat(client, const String:strCommand[], args)
{
	if(IsValidClient(client))
	{
		if(GetClientEvent(client) == EVENT_QUIZ && GetEventStatus(EVENT_QUIZ) == EVENT_STATUS_ACTIVE)
		{
			CPrintToChat(client, "{lawngreen}[QUIZ]{default} During the question period, all chat messages are blocked.");
		//	CPrintToChat(client, "{lawngreen}[QUIZ]{default} This measure is to help protect against griefing.");
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

public Action:OnPlayerDamaged(client, &attacker, &inflictor, &Float:damage, &damagetype) 
{
	if(IsValidClient(client))
	{
		if(GetClientEvent(client) == EVENT_QUIZ) {
			damage = 0.0;
			return Plugin_Changed;
		}
	}
	return Plugin_Continue;
}

public RespawnDelay(any:client)
{
	if(IsValidClient(client)) {
		TF2_RespawnPlayer(client);
	}
}

public Action:Command_Suicide(client, const String:strCommand[], args)
{
	if(IsValidClient(client))
	{
		if(GetEventStatus(EVENT_QUIZ) == EVENT_STATUS_ACTIVE)
		{
			if(GetClientEvent(client) == EVENT_QUIZ && g_iSuicideCount[client]-- > 0)
			{
				CPrintToChat(client, "{lawngreen}[QUIZ]{default} {fullred}[WARNING]{default} Commiting suicide will disqualify you.");
				if(g_iSuicideCount[client] != 0) CPrintToChat(client, "{lawngreen}[QUIZ] {gold}%d{default} suicide block%s remaining.", g_iSuicideCount[client], g_iSuicideCount[client] == 1 ? "" : "s");
				
				EmitSoundToClient(client, SOUND_WARNING, _, _, _, _, 0.25);
				
				return Plugin_Handled;
			}
		}
	}
	return Plugin_Continue;
}

public OnQuizTouch(const String:strOutput[], entity, activator, Float:flDelay)
{
	if(IsValidClient(activator)) {
		CreateParticipantMenu(activator, EVENT_QUIZ);
	}
}

public OnClientEventChanged(client, Event:event, Event:oldevent)
{
	if(IsValidClient(client))
	{
		if(event == EVENT_QUIZ)
		{
			SDKHook(client, SDKHook_OnTakeDamage, OnPlayerDamaged);
			
			TeleportToQuiz(client);		
			g_iSuicideCount[client] = SUICIDE_BLOCK_MAX;
			
			CPrintToChatAll("{lawngreen}[QUIZ]{default} Player %s%N{default} is now participating.",  GetClientTeam(client) == 2 ? "{red}" : "{blue}", client);
		}
		else if(oldevent == EVENT_QUIZ) {
			SDKUnhook(client, SDKHook_OnTakeDamage, OnPlayerDamaged);
			
			if(IsPlayerAlive(client)) TF2_RespawnPlayer(client);
			g_iSuicideCount[client] = SUICIDE_BLOCK_MAX;
		}
	}
}

public OnEventStatusChanged(Event:event, EventStatus:status)
{
	if(event == EVENT_QUIZ)
	{
		if(status == EVENT_STATUS_INACTIVE) {
			FireEntityInput("quiz_join_trigger", "Disable");
			FireEntityInput("quiz_join_prop", "Skin", "0");
			FireEntityInput("quiz_join_particle", "Stop");
			
			for(new i=1; i <= MaxClients; i++)
			{
				if(IsValidClient(i))
				{
					if(GetClientEvent(i) == EVENT_QUIZ) {
						SetClientEvent(i, EVENT_NONE);
					}
				}
			}
		}
		else if(status == EVENT_STATUS_SETUP) {
			FireEntityInput("quiz_join_trigger", "Enable");
			FireEntityInput("quiz_join_prop", "Skin", "1");
			FireEntityInput("quiz_join_particle", "Start");
		}
		else if(status == EVENT_STATUS_ACTIVE) {
			FireEntityInput("quiz_join_trigger", "Disable");
			FireEntityInput("quiz_join_prop", "Skin", "0");
			FireEntityInput("quiz_join_particle", "Stop");
		}
	}
}

TeleportToQuiz(any:client)
{
	new Float:vecOrigin[3], Float:vecAngle[3], Float:flAngle;
	
	GetClientAbsOrigin(client, vecOrigin);
	GetAngleToCoordinate(vecOrigin, VECTOR_LOOK_POINT, vecAngle)
	
	flAngle = GetRandomFloat(0.0, 1.0) * FLOAT_PI * 2.0;
	vecOrigin[0] = 0.0 + Cosine(flAngle) * 512.0;
	vecOrigin[1] = -4128.0 + Sine(flAngle) * 512.0;
	vecOrigin[2] = -256.0;
	
	TeleportEntity(client, vecOrigin, NULL_VECTOR, NULL_VECTOR);
}

stock GetAngleToCoordinate(const Float:vecOrigin[3], const Float:vecPoint[3], Float:vecAngle[3])
{
	new Float:vecAim[3];
	MakeVectorFromPoints(vecOrigin, vecPoint, vecAim);
	NormalizeVector(vecAim, vecAim);
	GetVectorAngles(vecAim, vecAngle);
}