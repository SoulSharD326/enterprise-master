#include <sourcemod>
#include <enterprise>

#define PLUGIN_VERSION 		"1.0.0"
#define INVALID_TIMESTAMP	0


new g_iLastActivity[MAXPLAYERS+1] = {INVALID_TIMESTAMP, ...};
new g_iLastWarning[MAXPLAYERS+1] = {0, ...};
new bool:g_bIsAFK[MAXPLAYERS+1] = {false, ...};

new Handle:gConVar[4] = {INVALID_HANDLE, ...};

public Plugin:myinfo = 
{
	name = "Enterprise - AFK Manager",
	author = "SoulSharD",
	description = "Manager for AFK players.",
	version = PLUGIN_VERSION,
	url = ""
};

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	// Natives:
	CreateNative("IsClientAFK", Native_IsClientAFK);
	return APLRes_Success;
}

public OnPluginStart()
{
	gConVar[0] = CreateConVar("sm_afk_threshold", "15", "How long no activity from the player is considered idle.");
	gConVar[1] = CreateConVar("sm_afk_warning_threshold", "0.5 0.75 0.9", "A percentage of 'sm_afk_threshold', where the server will warn the player is being AFK. (Insert multiple values with spaces)");
}

public OnGameFrame()
{
	static timestamp
	if(timestamp < GetTime()) 
	{
		OnTimestampTick();
		timestamp = GetTime();
	}
}

public OnClientDisconnect(client)
{
	g_iLastActivity[client] = INVALID_TIMESTAMP;
	g_bIsAFK[client] = false;
}

OnTimestampTick()
{
	for(new i=1; i <= MaxClients; i++)
	{
		if(IsValidClient(i))
		{
		//	if(!g_bIsAFK[i])
			{
				new time = GetTime() - g_iLastActivity[i];
				//PrintToChat(i, "Idle for: %d", time);
				
				if(time != GetTime())
				{
					if(time >= GetConVarInt(gConVar[0]))
					{
						
						g_bIsAFK[i] = true;
					} else {
						new String:strBuffer[128];
						new String:strThreshold[8][16];
						
						GetConVarString(gConVar[1], strBuffer, sizeof(strBuffer));
						new len = ExplodeString(strBuffer, " ", strThreshold, sizeof(strThreshold), sizeof(strThreshold[]));
						
						for(new x=0; x < len; x++)
						{
							new Float:flPercentage = time / GetConVarFloat(gConVar[0]);
							new Float:flThreshold = GetConVarFloat(gConVar[0]) * StringToFloat(strThreshold[x]);
							new String:strPercentage[8];
							
							
							Format(strPercentage, sizeof(strPercentage), "%.2f", flPercentage);
							PrintToChatAll("percent: %s", strPercentage);
							PrintToChatAll("thres: %s", strThreshold[x]);
							if(StringToFloat(strPercentage) == StringToFloat(strThreshold[x]))
							{
								if(g_iLastWarning[i] <= x)
								{
									g_iLastWarning[i] = x;
									PrintToChatAll("trorltorl");
								}
							}
						}
					}
				}
			}
		}
	}
}

public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon)
{
	//PrintToChatAll("%N: %d, %d, %0.f %0.f %0.f, %0.f %0.f %0.f, %d", client, buttons, impulse, vel[0], vel[1], vel[2], angles[0], angles[1], angles[2], weapon)

	for(new i=0; i < 25; i++)
	{
		new button = (1 << i);
		if(button & buttons) {
			g_iLastActivity[client] = GetTime();
		}
	}
	
	return Plugin_Continue;
}

public Native_IsClientAFK(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	return g_bIsAFK[client];
}