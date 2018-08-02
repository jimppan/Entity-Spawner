#if defined _entityspawner_included
 #endinput
#endif
#define _entityspawner_included

#define ES_PREFIX " \x09[\x04ES\x09]"
#define ES_MAX_ENTITIES 256
#define ES_INVALID_MAX_SPAWNS 0
#define ES_INVALID_SPAWN_INTERVAL 0
#define ES_INVALID_PROP_SEND_OFFSET -1
#define ES_INVALID_PROP_DATA_OFFSET -1

/**
 * Spawns random entities on the map (Set in entityspawner.cfg)
 * @return int 		amount of entities spawned
 */
native int ES_SpawnEntities();

/**
 * Clears all randomly spawned entities
 * @return int 		amount of entities removed
 */
native int ES_ClearEntities();

/**
 * Returns true if spawning is enabled on round start
 * @return bool		are entities spawning on round start
 */
native bool ES_IsSpawningOnRoundStart();

/**
 * Returns true if theres enough nav areas (Set by convar) and if config is setup for current map
 * @return bool		enough nav areas/config setup
 */
native bool ES_IsRandomSpawnsEnabled();

/**
 * Called when entities are randomly spawned across the map
 * @param entities that spawned (Entity references)
 * @param amount of entities spawned
 * @noreturn
 */
forward void ES_OnEntitiesSpawned(int entities[ES_MAX_ENTITIES], int entCount);

/**
 * Called when all randomly spawned entities are removed
 * @param amount of entities removed
 * @noreturn
 */
forward void ES_OnEntitiesCleared(int entCount);

public SharedPlugin __pl_entityspawner  =
{
	name = "entityspawner",
	file = "entityspawner.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public __pl_entityspawner_SetNTVOptional()
{	
	MarkNativeAsOptional("ES_SpawnEntities");
	MarkNativeAsOptional("ES_IsSpawningOnRoundStart");
	MarkNativeAsOptional("ES_IsRandomSpawnsEnabled");
}
#endif