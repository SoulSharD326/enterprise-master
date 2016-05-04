#include <sourcemod>
#include <enterprise>
#include <sdktools>
#include <sdkhooks>
#include <tf2>
#include <morecolors>

#define SMASHER_COOLDOWN_INTERVAL			5.0
#define SOUND_SUICIDE_ATTEMPT				"vo/engineer_no01.mp3"




#define ROTATOR_SPEED	"speed 50"

new bool:g_bHammertime = false;
new g_iNextClient = 0;
new g_iTarget = 0;

public OnPluginStart()
{
	if(IsServerProcessing()) {
		OnEntitiesInitalized();
	}

	RegConsoleCmd("sm_smasher", Command_Smasher);

	AddCommandListener(Command_Suicide, "kill");
	AddCommandListener(Command_Suicide, "explode");
	AddCommandListener(Command_Suicide, "spectate");
	AddCommandListener(Command_Suicide, "jointeam");
	AddCommandListener(Command_Suicide, "joinclass");
	
	HookEvent("player_spawn", Event_PlayerSpawn);
}

public Action:Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	//if(IsValidClient(client))
	{
		TeleportToSmasher(client);
	}
	return Plugin_Continue;
}

public OnMapStart()
{
	PrecacheSound(SOUND_SUICIDE_ATTEMPT);
	FireEntityInput("rotator_motor", "AddOutput", ROTATOR_SPEED);
}

public OnEntityCreated(entity, const String:strClassname[])
{
	if(StrEqual(strClassname, "func_breakable", false)) {
		SDKHook(entity, SDKHook_Spawn, OnBreakableSpawned);
	}
	else if(StrEqual(strClassname, "func_brush", false)) {
		SDKHook(entity, SDKHook_Spawn, OnBreakableSpawned);
	}
}

public Action:OnBreakableSpawned(entity)
{
	decl String:strTargetname[64];
	GetEntPropString(entity, Prop_Data, "m_iName", strTargetname, sizeof(strTargetname));
	if(StrEqual(strTargetname, "smasher_breakable", false))
	{
		new Float:vecOrigin[3], Float:flAngle = DegToRad(float(g_iNextClient-1) * 11.25);
		
		Format(strTargetname, sizeof(strTargetname), "smasher_breakable%d", g_iNextClient);
		SetEntPropString(entity, Prop_Data, "m_iName", strTargetname);
		
		vecOrigin[0] = 1216.0 * Cosine(flAngle);
		vecOrigin[1] = 1216.0 * Sine(flAngle);
		vecOrigin[2] = 0.0;
		
		TeleportEntity(entity, vecOrigin, Float:{0.0, flAngle, 0.0}, NULL_VECTOR);
	}
	else if(StrEqual(strTargetname, "smasher_brush", false))
	{
		new Float:vecOrigin[3], Float:flAngle = DegToRad(float(g_iNextClient-1) * 11.25);
	
		Format(strTargetname, sizeof(strTargetname), "smasher_breakable%d", g_iNextClient);
		SetEntPropString(entity, Prop_Data, "m_iName", strTargetname);
		
		vecOrigin[0] = 1216.0 * Cosine(flAngle);
		vecOrigin[1] = 1216.0 * Sine(flAngle);
		vecOrigin[2] = -8.0;
		
		TeleportEntity(entity, vecOrigin, Float:{0.0, flAngle, 0.0}, NULL_VECTOR);
	}
}

public OnEntitiesInitalized()
{
	HookSingleEntityOutput(FindSingleEntity("trigger_multiple", "smasher_join_trigger"), "OnStartTouch", OnSmasherTouch, false);
	HookSingleEntityOutput(FindSingleEntity("momentary_rot_button", "rotator_motor"), "OnReachedPosition", OnReachedPosition, false);
	// Note: SetPositionImmediately does NOT fire OnReachedPosition (the work around is to set its speed to an absurd value, and then set it to move via SetPosition)
	// We'll only need to use SetPositionImmediately when we don't need this output to fire (resetting the motor)
	
	new entity = -1;
	new String:strEntity[32];
	
	while((entity = FindEntityByClassname(entity, "prop_dynamic")) != -1)
	{
		GetEntPropString(entity, Prop_Data, "m_iName", strEntity, sizeof(strEntity));
		if(StrContains(strEntity, "smasher_pillar", false) != -1)
		{
			new Float:vecOrigin[3];
			
			GetEntPropVector(entity, Prop_Data, "m_vecOrigin", vecOrigin);
			vecOrigin[2] = -912.0;
			
			TeleportEntity(entity, vecOrigin, NULL_VECTOR, NULL_VECTOR);
		}
	}
}

public OnClientEventChanged(client, Event:event, Event:oldevent)
{
	//if(IsValidClient(client)
	{
		if(event == EVENT_SMASHER || oldevent == EVENT_SMASHER)
		{
			if(event == EVENT_SMASHER) TeleportToSmasher(client);
		}
	}
}

public OnClientDisconnect(client)
{
	if(client == g_iTarget) 
	{
		if(g_bHammertime) {
			CPrintToChatAll("{lawngreen}[SMASHER]{default} Player %s%N{default} cowardly disconnected before being smashed to pieces!", GetClientTeam(client) == 2 ? "{red}" : "{blue}", client);
		}
		g_iTarget = 0;
		SmasherInterval(INVALID_HANDLE);
	}
}

public Action:Command_Suicide(client, const String:strCommand[], args)
{
	if(IsValidClient(client))
	{
	//	if(GetEventStatus(EVENT_QUIZ) == EVENT_STATUS_ACTIVE)
		{
			if(client == g_iTarget && g_bHammertime) 
			{
				EmitSoundToClient(client, SOUND_SUICIDE_ATTEMPT);
				return Plugin_Handled;
			}
		}
	}
	return Plugin_Continue;
}

public OnSmasherTouch(const String:strOutput[], entity, activator, Float:flDelay)
{
	if(IsValidClient(activator)) {
		CreateParticipantMenu(activator, EVENT_SMASHER);
	}
}

public OnReachedPosition(const String:strOutput[], entity, activator, Float:flDelay)
{
	//if(GetEventStatus(EVENT_SMASHER) == EVENT_STATUS_ACTIVE)
	{
		g_bHammertime = true;
		
		if(g_iTarget != 0)
		{
			switch(GetRandomInt(1, 2))
			{
				case 1: {
					CreateTimer(1.3, SmasherDelay);
					FireEntityInput("rotator_hammer_relay1", "Trigger");
				}
				
				case 2: {
					CreateTimer(3.54, SmasherDelay);
					FireEntityInput("rotator_hammer_relay2", "Trigger");
				}
			}
		}
	}
/* 	else
	{
		wtf?
	} */
}

public Action:SmasherInterval(Handle:timer)
{
	new client = 0;
	new bool:bIsValid = false;
	new String:strDistance[32];
	
	do
	{
		client = GetRandomInt(1, MaxClients-1);
		//if(IsValidClient(client)) {
			///if(GetClientEvent(client) == EVENT_SMASHER) {
				bIsValid = true;
			///}
		//}
	} while(!bIsValid)
	
	PrintToChatAll("[%d] Picked: %N", client, client);
	
	Format(strDistance, sizeof(strDistance), "distance %f", (client - 1) * 11.25 + 360.0 * GetRandomInt(1, 3));
	
	FireEntityInput("rotator_motor", "SetPositionImmediately", "0.0");	
	FireEntityInput("rotator_motor", "AddOutput", strDistance);
	FireEntityInput("rotator_motor", "SetPosition", "1.0", 0.02);	
	
	g_iTarget = client;
}

public Action:SmasherDelay(Handle:timer)
{
	g_bHammertime = false;
	if(g_iTarget != 0)
	{
		new client = g_iTarget;
		//if(GetClientEvent(client) == EVENT_SMASHER)
		{
			//SetClientEvent(client, EVENT_NONE);
		//	TF2_RespawnPlayer(client);
			CPrintToChatAll("{lawngreen}[SMASHER]{default} Player %s%N{default} was smashed to pieces!", GetClientTeam(client) == 2 ? "{red}" : "{blue}", client);
		}
		
		g_iTarget = 0;
		CreateTimer(6.0, SmasherInterval);
		//CPrintToChatAll("{lawngreen}[SMASHER]{default} Spinning in 5 seconds...");
		AnnouncerCountdown(5, EVENT_SMASHER);
	}
}

public Action:Command_Smasher(client, args)
{
	CreateTimer(1.5, SmasherInterval);
	return Plugin_Handled;
}

TeleportToSmasher(any:client)
{
//	if(IsValidClient(client))
	{
		new Float:vecOrigin[3], Float:flAngle = DegToRad(float(client-1) * 11.25);
		
		vecOrigin[0] = 1216.0 * Cosine(flAngle);
		vecOrigin[1] = 1216.0 * Sine(flAngle);
		vecOrigin[2] = 28.0;
		
		TeleportEntity(client, vecOrigin, NULL_VECTOR, NULL_VECTOR);
	}
}