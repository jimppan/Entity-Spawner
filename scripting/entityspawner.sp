#pragma semicolon 1

//#define DEBUG

#define PLUGIN_AUTHOR "Rachnus"
#define PLUGIN_VERSION "1.01"

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <navareautilities>
#include <entityspawner>

#pragma newdecls required

ConVar g_NavAreasRequired;
ConVar g_SpawnLimit;

KeyValues g_hRandomSpawns;

int g_iEntityCount = 0;
int g_iEntities[ES_MAX_ENTITIES] =  { INVALID_ENT_REFERENCE, ... };
int g_iTimesSpawned = 0;
int g_iMaxSpawns = ES_INVALID_MAX_SPAWNS;
int g_iSpawnInterval = 0;
bool g_bResetTimer = false;

bool g_bRandomSpawnsEnabled = false;
bool g_bSpawnOnRoundStart = false;

Handle g_hTimerSpawn = null;

// Forwards
Handle g_hOnEntitiesSpawned;
Handle g_hOnEntitiesCleared;

public Plugin myinfo = 
{
	name = "Entity Spawner CSGO v1.01",
	author = PLUGIN_AUTHOR,
	description = "Spawn entities at random points on the map (Nav Areas)",
	version = PLUGIN_VERSION,
	url = "https://github.com/Rachnus"
};

public void OnPluginStart()
{
	if(GetEngineVersion() != Engine_CSGO)
		SetFailState("This plugin is for CSGO only.");
	
	HookEvent("round_start", Event_RoundStart, EventHookMode_Post);
	
	g_NavAreasRequired = 	CreateConVar("entityspawner_nav_areas_required", "50", "Amount of nav areas required for items to spawn");
	g_SpawnLimit = 			CreateConVar("entityspawner_spawn_limit", "1900", "Stop spawning entities once global entity count reaches this value");
	g_hOnEntitiesSpawned =	CreateGlobalForward("ES_OnEntitiesSpawned", ET_Ignore, Param_Array, Param_Cell);
	g_hOnEntitiesCleared =	CreateGlobalForward("ES_OnEntitiesCleared", ET_Ignore, Param_Cell);
	
	RegAdminCmd("sm_esspawn", Command_Spawn, ADMFLAG_ROOT);
	RegAdminCmd("sm_esclear", Command_Clear, ADMFLAG_ROOT);
	RegAdminCmd("sm_esreload", Command_Reload, ADMFLAG_ROOT);
	
	//ONLY UNCOMMENT WHEN DEBUGGING
	//char map[PLATFORM_MAX_PATH];
	//GetCurrentMap(map, sizeof(map));
	//g_bRandomSpawnsEnabled = LoadRandomSpawns(map);
}

public void OnPluginEnd()
{
	ClearEntities();
}

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int err_max)
{
	CreateNative("ES_SpawnEntities", Native_SpawnEntities);
	CreateNative("ES_ClearEntities", Native_ClearEntities);
	CreateNative("ES_IsSpawningOnRoundStart", Native_IsSpawningOnRoundStart);
	CreateNative("ES_IsRandomSpawnsEnabled", Native_IsRandomSpawnsEnabled);
	
	RegPluginLibrary("entityspawner");
	return APLRes_Success;
}

public int Native_SpawnEntities(Handle plugin, int numParams)
{
	return SpawnEntities();
}

public int Native_ClearEntities(Handle plugin, int numParams)
{
	return ClearEntities();
}

public int Native_IsSpawningOnRoundStart(Handle plugin, int numParams)
{
	return g_bSpawnOnRoundStart;
}

public int Native_IsRandomSpawnsEnabled(Handle plugin, int numParams)
{
	return g_bRandomSpawnsEnabled;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if(g_bRandomSpawnsEnabled)
	{
		if(g_bResetTimer)
			KillSpawnTimer();
		
		if(g_iMaxSpawns > ES_INVALID_MAX_SPAWNS && g_iTimesSpawned >= g_iMaxSpawns)
		{
			ClearEntities();
			return Plugin_Continue;
		}

		if(g_iSpawnInterval > ES_INVALID_SPAWN_INTERVAL && g_bResetTimer)
			StartSpawnTimer();
		
		if(g_bSpawnOnRoundStart)
		{
			SpawnEntities();
			g_iTimesSpawned++;
		}
	}
	return Plugin_Continue;
}

public Action Command_Spawn(int client, int args)
{
	if(!g_bRandomSpawnsEnabled)
	{
		PrintToChat(client, "%s \x07Random spawns are disabled on this map.", ES_PREFIX);
		return Plugin_Handled;
	}
	int count = SpawnEntities();
	PrintToChat(client, "%s Spawned \x04%d\x09 entities.", ES_PREFIX, count);
	return Plugin_Handled;
}

public Action Command_Clear(int client, int args)
{
	int count = ClearEntities();
	PrintToChat(client, "%s Removed \x04%d\x09 entities.", ES_PREFIX, count);
	return Plugin_Handled;
}

public Action Command_Reload(int client, int args)
{
	char map[PLATFORM_MAX_PATH];
	GetCurrentMap(map, sizeof(map));
	g_bRandomSpawnsEnabled = LoadRandomSpawns(map);
	PrintToChat(client, "%s Config reloaded!", ES_PREFIX);
	return Plugin_Handled;
}

public int ClearEntities()
{
	int count = 0;
	for (int i = 0; i < ES_MAX_ENTITIES; i++)
	{
		int ent = EntRefToEntIndex(g_iEntities[i]);
		if(ent != INVALID_ENT_REFERENCE && IsValidEntity(ent))
		{
			count++;
			AcceptEntityInput(ent, "Kill");
		}
		g_iEntities[i] = INVALID_ENT_REFERENCE;
	}
	g_iEntityCount = 0;
	
	Call_StartForward(g_hOnEntitiesCleared);
	Call_PushCell(count);
	Call_Finish();
	
	return count;
}

public void ApplyEntityKeyvalues(int entity, const char[] section)
{
	int counter = 0;
	// Get all keyvalues
	for (; ;)
	{
		char temp[32];
		Format(temp, sizeof(temp), "keyvalue%d", counter++);
		
		char value[PLATFORM_MAX_PATH + 32];
		g_hRandomSpawns.GetString(temp, value, sizeof(value), "STOP");
		
		if(StrEqual(value, "STOP", false))
			break;
			
		char exploded[2][PLATFORM_MAX_PATH];
		ExplodeString(value, " ", exploded, 2, sizeof(exploded[]));
	
		if(!DispatchKeyValue(entity, exploded[0], exploded[1]))
			SetFailState("Could not set value \"%s\" on key \"%s\" in section \"%s\". ERROR: ApplyEntityKeyvalues.", exploded[1], exploded[0], section);
	}
}

public void ApplyEntityProps(int entity, const char[] section)
{
	int counter = 0;
	char className[PLATFORM_MAX_PATH], value[PLATFORM_MAX_PATH + 32], temp[32];
	GetEntityNetClass(entity, className, sizeof(className));
	
	PropFieldType sendFieldType = PropField_Unsupported;
	PropFieldType dataFieldType = PropField_Unsupported;

	for (; ;)
	{

		Format(temp, sizeof(temp), "prop%d", counter++);
		g_hRandomSpawns.GetString(temp, value, sizeof(value), "STOP");
		
		if(StrEqual(value, "STOP", false))
			break;
			
		char exploded[4][PLATFORM_MAX_PATH];
		ExplodeString(value, " ", exploded, 4, sizeof(exploded[]));
		
		bool send = false;
		bool data = false;
		
		if(FindSendPropInfo(className, exploded[0], sendFieldType) != ES_INVALID_PROP_SEND_OFFSET)
			send = true;
			
		if(FindDataMapInfo(entity, exploded[0], dataFieldType) != ES_INVALID_PROP_DATA_OFFSET)
			data = true;
		
		if(!send && !data)
			SetFailState("Could not find prop \"%s\"  in section \"%s\". ERROR: ApplyEntityProps.", exploded[0], section);
		
		if(send)
		{
			switch(sendFieldType)
			{
				case PropField_Integer:
				{
					int iValue = StringToInt(exploded[1]);
					SetEntProp(entity, Prop_Send, exploded[0], iValue);
				}
				case PropField_Float:
				{
					float fValue = StringToFloat(exploded[1]);
					SetEntPropFloat(entity, Prop_Send, exploded[0], fValue);

				}
				case PropField_String:
				{
					SetEntPropString(entity, Prop_Send, exploded[0], exploded[1]);
				}
				case PropField_String_T:
				{
					SetEntPropString(entity, Prop_Send, exploded[0], exploded[1]);
				}
				case PropField_Vector:
				{
					float vecValue[3];
					vecValue[0] = StringToFloat(exploded[1]);
					vecValue[1] = StringToFloat(exploded[2]);
					vecValue[2] = StringToFloat(exploded[3]);
					SetEntPropVector(entity, Prop_Send, exploded[0], vecValue);
				}
				case PropField_Entity:
				{
					int iValue = StringToInt(exploded[1]);
					SetEntPropEnt(entity, Prop_Send, exploded[0], iValue);
				}
			}
		}
		
		if(data)
		{
			switch(dataFieldType)
			{
				case PropField_Integer:
				{
					int iValue = StringToInt(exploded[1]);
					SetEntProp(entity, Prop_Data, exploded[0], iValue);
				}
				case PropField_Float:
				{
					float fValue = StringToFloat(exploded[1]);
					SetEntPropFloat(entity, Prop_Data, exploded[0], fValue);

				}
				case PropField_String:
				{
					SetEntPropString(entity, Prop_Data, exploded[0], exploded[1]);
				}
				case PropField_String_T:
				{
					SetEntPropString(entity, Prop_Data, exploded[0], exploded[1]);
				}
				case PropField_Vector:
				{
					float vecValue[3];
					vecValue[0] = StringToFloat(exploded[1]);
					vecValue[1] = StringToFloat(exploded[2]);
					vecValue[2] = StringToFloat(exploded[3]);
					SetEntPropVector(entity, Prop_Data, exploded[0], vecValue);
				}
				case PropField_Entity:
				{
					int iValue = StringToInt(exploded[1]);
					SetEntPropEnt(entity, Prop_Data, exploded[0], iValue);
				}
			}
		}
	}
}

public int SpawnEntities()
{
	ClearEntities();
	
	g_hRandomSpawns.Rewind();
	
	if(!g_hRandomSpawns.GotoFirstSubKey())
		return 0;
	
	int entCount = 0;
	
	char section[PLATFORM_MAX_PATH];
	char className[32];
	int maxSpawns = 0;
	
	do 
	{
		if(entCount >= ES_MAX_ENTITIES)
			break;
		
		g_hRandomSpawns.GetSectionName(section, sizeof(section));
		
		g_hRandomSpawns.GetString("classname", className, sizeof(className), "STOP");
		if(StrEqual(className, "STOP", true))
			SetFailState("Could not parse entities.cfg. Missing \"classname\" field in section \"%s\".", section);
		
		maxSpawns = g_hRandomSpawns.GetNum("maxspawns", -1);
		if(maxSpawns <= 0 || maxSpawns > ES_MAX_ENTITIES)
			SetFailState("Invalid \"maxspawns\" value in section \"%s\". 0 - %d", ES_MAX_ENTITIES, section);
		
		for (int i = 0; i < maxSpawns; i++)
		{
			if(GetEntityCount() >= g_SpawnLimit.IntValue)
				break;
			
			float pos[3], vMins[3], vMaxs[3];
			CNavArea navArea = NAU_GetNavAreaAddressByIndex(GetRandomInt(0, NAU_GetNavAreaCount() - 1));

			int entity = CreateEntityByName(className);
			if(!IsValidEntity(entity))
				SetFailState("Could not spawn \"%s\" in section \"%s\". Invalid entity.", className, section);
			

			ApplyEntityKeyvalues(entity, section);
			
			if(!DispatchSpawn(entity))
				SetFailState("Could not spawn \"%s\" in section \"%s\". ERROR: DispatchSpawn.", className, section);
			
			ApplyEntityProps(entity, section);
			
			GetEntPropVector(entity, Prop_Data, "m_vecMins", vMins);
			GetEntPropVector(entity, Prop_Data, "m_vecMaxs", vMaxs);
			// 
			if(navArea.GetRandomPos(vMins, vMaxs, pos))
			{
				if(!g_hRandomSpawns.GetNum("slopes", 0) && navArea.GetZDifference() != 0.0)
				{
					AcceptEntityInput(entity, "Kill");
					continue;
				}
				
				pos[2] += -vMins[2] + g_hRandomSpawns.GetFloat("zoffset", 0.0);
				if(!NAU_IsPositionBlocked(pos, vMins, vMaxs))
				{
					g_iEntities[g_iEntityCount++] = EntIndexToEntRef(entity);
					TeleportEntity(entity, pos, NULL_VECTOR, NULL_VECTOR);
					entCount++;
				}
				else
					AcceptEntityInput(entity, "Kill");
			}
			else
				AcceptEntityInput(entity, "Kill");

			if(entCount >= ES_MAX_ENTITIES)
				break;
		}
		
		if(GetEntityCount() >= g_SpawnLimit.IntValue)
			break;
		
	} while (g_hRandomSpawns.GotoNextKey());
	
	Call_StartForward(g_hOnEntitiesSpawned);
	Call_PushArray(g_iEntities, ES_MAX_ENTITIES);
	Call_PushCell(entCount);
	Call_Finish();
	
#if defined DEBUG
		PrintToServer("Spawned %d entities", entCount);
#endif
	
	return entCount;
}

public bool LoadRandomSpawns(const char[] map)
{
	if(NAU_GetNavAreaCount() < g_NavAreasRequired.IntValue)
		return false;
	
	KeyValues temp;
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/entityspawner/entities.cfg");
	temp = new KeyValues("entities");
	
	if(!temp.ImportFromFile(path))
		SetFailState("Could not open %s", path);
	temp.SetEscapeSequences(true);
	
	
	bool foundMatch = false;
	temp.Rewind();
	if(!temp.GotoFirstSubKey())
		return false;
	
	char mapCheck[PLATFORM_MAX_PATH];
	do 
	{
		temp.GetSectionName(mapCheck, sizeof(mapCheck));
		if(StrContains(map, mapCheck, false) != -1)
		{
			foundMatch = true;
			break;
		}
	} while (temp.GotoNextKey());
	
	if(!foundMatch)
		return false;

	g_hRandomSpawns = new KeyValues("entities");
	g_hRandomSpawns.Import(temp);
	g_hRandomSpawns.Rewind();
	g_bSpawnOnRoundStart = !!g_hRandomSpawns.GetNum("spawnroundstart", 1);
	g_iMaxSpawns = g_hRandomSpawns.GetNum("maxroundspawns", ES_INVALID_MAX_SPAWNS);
	g_iSpawnInterval = g_hRandomSpawns.GetNum("spawninterval", ES_INVALID_SPAWN_INTERVAL);
	g_bResetTimer = !!g_hRandomSpawns.GetNum("resettimer", 1);
	
	if(g_iSpawnInterval > ES_INVALID_SPAWN_INTERVAL)
		StartSpawnTimer();
	
	PrecacheEntities();
	return true;
}

public void PrecacheEntities()
{
	g_hRandomSpawns.Rewind();
	
	if(!g_hRandomSpawns.GotoFirstSubKey())
		return;

	do 
	{
		int counter = 0;
		// Get all keyvalues
		for (; ;)
		{
			char temp[32];
			Format(temp, sizeof(temp), "keyvalue%d", counter++);
			
			char value[PLATFORM_MAX_PATH + 32];
			g_hRandomSpawns.GetString(temp, value, sizeof(value), "STOP");
			
			if(StrEqual(value, "STOP", false))
				break;
				
			char exploded[2][PLATFORM_MAX_PATH];
			ExplodeString(value, " ", exploded, 2, sizeof(exploded[]));
			
			if(StrEqual(exploded[0], "model", false))
			{
#if defined DEBUG
				PrintToServer("PRECACHED MODEL %s", exploded[1]);
#endif
				PrecacheModel(exploded[1]);
			}
		}
	} while (g_hRandomSpawns.GotoNextKey());
}

public void StartSpawnTimer()
{
	KillSpawnTimer();
	g_hTimerSpawn = CreateTimer(float(g_iSpawnInterval), Timer_Spawn, _, TIMER_REPEAT);
}

public void KillSpawnTimer()
{
	if(g_hTimerSpawn != null)
		KillTimer(g_hTimerSpawn);
	g_hTimerSpawn = null;
}

public Action Timer_Spawn(Handle timer, any data)
{
	SpawnEntities();
}

// Called on map start
public void NAU_OnNavAreasLoaded()
{
	char map[PLATFORM_MAX_PATH];
	GetCurrentMap(map, sizeof(map));
	g_bRandomSpawnsEnabled = LoadRandomSpawns(map);
}

public void OnMapEnd()
{
	KillSpawnTimer();
}