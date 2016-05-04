#include <sourcemod>
#include <enterprise>
#include <sdktools>

#define PLUGIN_VERSION		"1.0.0"	

new Handle:g_adtArray = INVALID_HANDLE;

public Plugin:myinfo = 
{
	name = "Enterprise - Decals",
	author = PLUGIN_AUTHOR,
	description = "Handles decal materials for the Enterprise map.",
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
};

public OnPluginStart()
{
	g_adtArray = CreateArray();
	if(!LoadDecalData()) {
		SubmitToLog(LOG_ERROR, "Failed to load map decals.");
	}
}

public OnClientPostAdminCheck(client)
{
	new Float:vecOrigin[3];
	new Handle:index;
	new precacheID;
	
	new size = GetArraySize(g_adtArray);
	for(new i=0; i < size; i++)
	{
		index = GetArrayCell(g_adtArray, i);
		vecOrigin[0] = Float:GetArrayCell(index, 0);
		vecOrigin[1] = Float:GetArrayCell(index, 1);
		vecOrigin[2] = Float:GetArrayCell(index, 2);
		precacheID = GetArrayCell(index, 3);
		
		TE_SetupBSPDecal(vecOrigin, 0, precacheID);
		TE_SendToClient(client);
	}
}

LoadDecalData()
{
	ClearArray(g_adtArray);
	
	decl String:strPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, strPath, sizeof(strPath), "configs/enterprise/decals.cfg");
	
	if(FileExists(strPath))
	{
		new Handle:kv = CreateKeyValues("Decals");
		if(FileToKeyValues(kv, strPath) && KvGotoFirstSubKey(kv))
		{
			do
			{
				decl String:strMaterial[PLATFORM_MAX_PATH], String:strVTF[PLATFORM_MAX_PATH], String:strVMT[PLATFORM_MAX_PATH];
				KvGetSectionName(kv, strMaterial, sizeof(strMaterial));
				new decalIndex = PrecacheDecal(strMaterial, true);
				
				Format(strVMT, sizeof(strVMT), "materials/%s.vmt", strMaterial);
				AddFileToDownloadsTable(strVMT);
				
				new Handle:vtf = CreateKeyValues("LightmappedGeneric");
				KvGetString(vtf, "$basetexture", strMaterial, sizeof(strMaterial), strMaterial);
				CloseHandle(vtf);
				
				Format(strVTF, sizeof(strVTF), "materials/%s.vtf", strMaterial);
				AddFileToDownloadsTable(strVTF);
				
				new Float:vecPosition[3];
				decl String:strPosition[16];
				
				new i=1;
				Format(strPosition, sizeof(strPosition), "origin%d", i);
				
				KvGetVector(kv, strPosition, vecPosition);
				while(vecPosition[0]+vecPosition[1]+vecPosition[2] != 0.0)
				{
					new Handle:adtDecal = CreateArray(4);
					PushArrayCell(adtDecal, vecPosition[0]);
					PushArrayCell(adtDecal, vecPosition[1]);
					PushArrayCell(adtDecal, vecPosition[2]);
					PushArrayCell(adtDecal, decalIndex);
					PushArrayCell(g_adtArray, adtDecal);
					
					Format(strPosition, sizeof(strPosition), "origin%d", i++);
					KvGetVector(kv, strPosition, vecPosition);
				}
			} while(KvGotoNextKey(kv));
			if(kv != INVALID_HANDLE) CloseHandle(kv);		
			return true;
		}
		if(kv != INVALID_HANDLE) CloseHandle(kv);
		return false;
	}
	return false;
}

TE_SetupBSPDecal(const Float:vecOrigin[3], entity, index)
{
	TE_Start("BSP Decal");
	TE_WriteVector("m_vecOrigin", vecOrigin);
	TE_WriteNum("m_nEntity", entity);
	TE_WriteNum("m_nIndex", index);
}

