#include <sourcemod>
#include <enterprise>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>

#define SOUND_TELEPORT_SEND				"weapons/teleporter_send.wav"
#define SOUND_TELEPORT_RECEIVE			"weapons/teleporter_receive.wav"
//#define CAMERA_REFRESH_RATE				0.1
#define CAMERA_MAX_RANGE				1024.0

#define MODEL_BREAD1 			"models/weapons/c_models/c_bread/c_bread_baguette.mdl"
#define MODEL_BREAD2 			"models/weapons/c_models/c_bread/c_bread_burnt.mdl"
#define MODEL_BREAD3 			"models/weapons/c_models/c_bread/c_bread_cinnamon.mdl"
#define MODEL_BREAD4 			"models/weapons/c_models/c_bread/c_bread_cornbread.mdl"
#define MODEL_BREAD5 			"models/weapons/c_models/c_bread/c_bread_crumpet.mdl"
#define MODEL_BREAD6 			"models/weapons/c_models/c_bread/c_bread_plainloaf.mdl"
#define MODEL_BREAD7 			"models/weapons/c_models/c_bread/c_bread_pretzel.mdl"
#define MODEL_BREAD8 			"models/weapons/c_models/c_bread/c_bread_ration.mdl"
#define MODEL_BREAD9 			"models/weapons/c_models/c_bread/c_bread_russianblack.mdl"

new Handle:gConVar[3] = {INVALID_HANDLE, ...};
new Handle:g_hTimeAdjust = INVALID_HANDLE;

public OnPluginStart()
{
	gConVar[0] = CreateConVar("sm_disco_panel_interval", "3.0");

	if(IsServerProcessing()) {
		OnEntitiesInitialized();
	}

	RegConsoleCmd("sm_setevent", Command_SetEvent);
	RegConsoleCmd("sm_initiateevent", Command_InitiateEvent);
	g_hTimeAdjust = CreateConVar("sm_clock_adjust", "0");
}

public OnMapStart()
{
	PrecacheSound(SOUND_TELEPORT_SEND);
	PrecacheSound(SOUND_TELEPORT_RECEIVE);
	
	PrecacheModel(MODEL_BREAD1);
	PrecacheModel(MODEL_BREAD2);
	PrecacheModel(MODEL_BREAD3);
	PrecacheModel(MODEL_BREAD4);
	PrecacheModel(MODEL_BREAD5);
	PrecacheModel(MODEL_BREAD6);
	PrecacheModel(MODEL_BREAD7);
	PrecacheModel(MODEL_BREAD8);
	PrecacheModel(MODEL_BREAD9);
}

public OnGameFrame()
{
	static timestamp
	if(timestamp < GetTime())
	{
		timestamp = GetTime();
		ProcessTimedEvents(timestamp);
	}
}

ProcessTimedEvents(timestamp)
{
	timestamp += GetConVarInt(g_hTimeAdjust);

	new String:strSecond[4], String:strMinute[4],
		String:strHour[4];
		
	FormatTime(strSecond, sizeof(strSecond), "%S", timestamp);
	FormatTime(strMinute, sizeof(strMinute), "%M", timestamp);
	FormatTime(strHour, sizeof(strHour), "%H", timestamp);
	
	SetTextureIndex("clock_colon", StringToInt(strSecond) % 2);
	
	SetTextureIndex("clock_minute2", GetNumberInString(0, strMinute));
	SetTextureIndex("clock_minute1", GetNumberInString(1, strMinute));
	
	SetTextureIndex("clock_hour2", GetNumberInString(0, strHour));
	SetTextureIndex("clock_hour1", GetNumberInString(1, strHour));
}

public OnEntitiesInitialized()
{
	new entity = -1, String:strEntity[64];
	
	new Float:flRate = GetRandomFloat(1.2, 2.0);
	new Float:vecAngle[3];
	vecAngle[1] = GetRandomFloat(0.0, 360.0);
	
	while((entity = FindEntityByClassname(entity, "prop_dynamic")) != -1)
	{
		GetEntPropString(entity, Prop_Data, "m_iName", strEntity, sizeof(strEntity));
		if(StrEqual(strEntity, "arena_flag", false))
		{
			SetVariantFloat(flRate);
			AcceptEntityInput(entity, "SetPlaybackRate");
			TeleportEntity(entity, NULL_VECTOR, vecAngle, NULL_VECTOR);
		}
	}
	
	while((entity = FindEntityByClassname(entity, "trigger_teleport")) != -1)
	{
		new Float:vecMin[3], Float:vecMax[3];

		GetEntPropVector(entity, Prop_Send, "m_vecMins", vecMin);
		GetEntPropVector(entity, Prop_Send, "m_vecMaxs", vecMax);

		new Float:x = vecMin[0] + vecMax[0];
		new Float:y = vecMin[1] + vecMax[1];
		new Float:z = vecMin[2] + vecMax[2];
		if(x * y * z <= 2376)
		{
			HookSingleEntityOutput(entity, "OnEndTouch", OnTeleport, false)
		}
	}
	
	while((entity = FindEntityByClassname(entity, "prop_dynamic")) != -1)
	{
		GetEntPropString(entity, Prop_Data, "m_iName", strEntity, sizeof(strEntity));
		if(StrContains(strEntity, "func_camera", false) != -1)
		{
			RequestFrame(OnCameraThink, EntIndexToEntRef(entity));
			//CreateTimer(CAMERA_REFRESH_RATE, OnCameraThink, EntIndexToEntRef(entity), TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		}
	}
	
	DiscoPanelInterval(INVALID_HANDLE);
}

public Action:Command_SetEvent(client, args)
{
	new String:arg1[8];
	new String:arg2[8];
	
	GetCmdArg(1, arg1, sizeof(arg1));
	GetCmdArg(2, arg2, sizeof(arg2));
	
	new event = StringToInt(arg1);
	new status = StringToInt(arg2);
	
	SetEventStatus(Event:event, EventStatus:status);
	return Plugin_Handled;
}

public Action:Command_InitiateEvent(client, args)
{
	new String:arg1[8];
	new String:arg2[8];
	new String:arg3[8];
	new String:arg4[8];
	
	GetCmdArg(1, arg1, sizeof(arg1));
	GetCmdArg(2, arg2, sizeof(arg2));
	GetCmdArg(3, arg3, sizeof(arg3));
	GetCmdArg(4, arg4, sizeof(arg4));
	
	new event = StringToInt(arg1);
	new time = StringToInt(arg2);
	new minplayers = StringToInt(arg3);
	new maxplayers = StringToInt(arg4);
	
	InitiateEventSetup(event, time, minplayers, maxplayers);
	return Plugin_Handled;
}

public Action:DiscoPanelInterval(Handle:timer)
{
	new String:strEntity[64];
/* 	new String:strColour[][] = {
		"255 0 0", // Red
		"0 255 0", // Green
		"0 0 255", // Blue
		"0 255 255", // Cyan
		"255 128 0", // Orange
		"255 0 255", // Purple
		"255 0 128", // Pink
		"255 255 0" // Yellow
	}; */
	
	new String:strColour[16];
	for(new i=1; i <= 36; i++)
	{
		Format(strEntity, sizeof(strEntity), "disco_panel%d", i);
		Format(strColour, sizeof(strColour), "%d %d %d", GetRandomInt(0, 255),  GetRandomInt(0, 255),  GetRandomInt(0, 255));	
		FireEntityInput(strEntity, "Color", strColour);
	}
	
	CreateTimer(GetConVarFloat(gConVar[0]), DiscoPanelInterval);
	return Plugin_Stop;
}

public OnCameraThink(any:ref)
{
	new entity = EntRefToEntIndex(ref);
	if(entity != INVALID_ENT_REFERENCE)
	{
		new Float:vecOrigin[3], Float:vecPosition[3];
		
		GetEntPropVector(entity, Prop_Data, "m_vecOrigin", vecOrigin);
		
		new client = -1, Float:flNearest = CAMERA_MAX_RANGE;
		for(new i=1; i <= MaxClients; i++)
		{
			if(IsValidClient(i))
			{
				if(IsPlayerAlive(i))
				{
					new Float:vecBounds[3];
					GetEntPropVector(i, Prop_Data, "m_vecOrigin", vecPosition);
					GetEntPropVector(i, Prop_Send, "m_vecMaxs", vecBounds);
					
					vecPosition[2] += (vecBounds[2] * 0.75);
					new Float:flDistance = GetVectorDistance(vecOrigin, vecPosition);
					if(flDistance < CAMERA_MAX_RANGE && flDistance < flNearest)
					{
						TR_TraceRayFilter(vecOrigin, vecPosition, MASK_VISIBLE, RayType_EndPoint, TraceRayNoPlayers, entity);
						if(!TR_DidHit())
						{
							flNearest = flDistance;
							client = i;	
						}
					}
				}
			}
		}
		
		if(client != -1)
		{
			new Float:vecAngle[3];
			GetAngleToCoordinate(vecOrigin, vecPosition, vecAngle);
			
			new Float:flTemp = vecAngle[0];
			vecAngle[0] = vecAngle[2];
			vecAngle[1] -= 90.0;
			vecAngle[2] = 0.0 - flTemp;
	
			TeleportEntity(entity, NULL_VECTOR, vecAngle, NULL_VECTOR);
		}
		RequestFrame(OnCameraThink, ref);
	}
}

stock GetAngleToCoordinate(const Float:vecOrigin[3], const Float:vecPoint[3], Float:vecAngle[3])
{
	new Float:vecAim[3];
	MakeVectorFromPoints(vecOrigin, vecPoint, vecAim);
	NormalizeVector(vecAim, vecAim);
	GetVectorAngles(vecAim, vecAngle);
}

public bool:TraceRayNoPlayers(entity, mask, any:data)
{
	if(entity == data || (entity >= 1 && entity <= MaxClients)) {
		return false;
	}
	return true;
} 

public OnTeleport(const String:strOutput[], entity, activator, Float:flDelay)
{
	new Float:vecOrigin[3],  Float:vecVelocity[3], Float:vecMin[3];
	
	GetEntPropVector(entity, Prop_Send, "m_vecMins", vecMin);
	GetEntPropVector(entity, Prop_Data, "m_vecOrigin", vecOrigin);
	vecOrigin[2] += vecMin[2];
	
	TF2_AddCondition(activator, TFCond_TeleportedGlow, 10.0, 0);
	TeleportEntity(activator, NULL_VECTOR, NULL_VECTOR, vecVelocity);
	
	if(GetClientTeam(activator) == _:TFTeam_Red) {
		CreateParticle(vecOrigin, "teleported_red");
		CreateParticle(vecOrigin, "teleportedin_red");
	} else {
		CreateParticle(vecOrigin, "teleported_blue");
		CreateParticle(vecOrigin, "teleportedin_blue");
	}
	
	new pitch = GetRandomInt(75, 100);
	EmitAmbientSound(SOUND_TELEPORT_SEND, vecOrigin, entity, _, _, _, pitch);
	
	GetClientAbsOrigin(activator, vecOrigin);
	EmitAmbientSound(SOUND_TELEPORT_RECEIVE, vecOrigin, activator, _, _, _, pitch);
	
	if(GetRandomFloat(0.0, 1.0) <= 0.05)
	{
		for(new i=0; i < 10; i++) {
			SpawnBread(vecOrigin);
		}
	}
}

SpawnBread(Float:vecOrigin[3])
{
	new entity = CreateEntityByName("prop_physics_override");
	if(IsValidEdict(entity))
	{
		new Float:vecAngle[3], Float:vecVelocity[3];
		
		switch(GetRandomInt(1, 9))
		{
			case 1: SetEntityModel(entity, MODEL_BREAD1);
			case 2: SetEntityModel(entity, MODEL_BREAD2);
			case 3: SetEntityModel(entity, MODEL_BREAD3);
			case 4: SetEntityModel(entity, MODEL_BREAD4);
			case 5: SetEntityModel(entity, MODEL_BREAD5);
			case 6: SetEntityModel(entity, MODEL_BREAD6);
			case 7: SetEntityModel(entity, MODEL_BREAD7);
			case 8: SetEntityModel(entity, MODEL_BREAD8);
			case 9: SetEntityModel(entity, MODEL_BREAD9);
		}
		
		DispatchKeyValue(entity, "spawnflags", "4");
		DispatchKeyValue(entity, "disableshadows", "1");
		DispatchSpawn(entity);
		
		vecAngle[0] = GetRandomFloat(0.0, 360.0);
		vecAngle[1] = GetRandomFloat(0.0, 360.0);
		vecAngle[2] = GetRandomFloat(0.0, 360.0);
		
		vecVelocity[0] = GetRandomFloat(-100.0, 100.0);
		vecVelocity[1] = GetRandomFloat(-100.0, 100.0);
		
		TeleportEntity(entity, vecOrigin, vecAngle, vecVelocity);
		ActivateEntity(entity);
		
		DeleteEdict(entity, GetRandomFloat(4.0, 6.0));
		return entity;
	}	
	return -1;
}



GetNumberInString(index, const String:strBuffer[])
{
	decl String:strNumber[2];
	Format(strNumber, sizeof(strNumber), "%c", strBuffer[index]);
	return StringToInt(strNumber);
}