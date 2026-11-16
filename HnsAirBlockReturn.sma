#include <amxmodx>
#include <hamsandwich>
#include <fakemeta>
#include <reapi>
#include <hns_matchsystem>

enum _:KillfeedType {
  KILLFEED_NONE,
  KILLFEED_BLOCK,
  KILLFEED_FLASH
}

enum _:Player {
  bool: is_touched,
  bool: is_full_flashed,
  bool: is_blocked,
  toucher,
  flasher,
  last_frames,
  killfeed_actor,
  killfeed_type
}

new player[MAX_PLAYERS + 1][Player]
new Array: player_origin[MAX_PLAYERS + 1]
new Array: player_angles[MAX_PLAYERS + 1]

new prefix[24]
new airblock_return
new Float: airblock_damage
new airblock_chat
new airblock_killfeed

public plugin_init() {
  register_plugin("HNS: Block return", "2.4", "OpenHNS") // Garey, ufame

  RegisterHookChain(RG_CSGameRules_FlPlayerFallDamage, "@RG_CSGameRules_FlPlayerFallDamage", true)
  RegisterHookChain(RG_CBasePlayer_PreThink, "@RG_CBasePlayer_PreThink")
  RegisterHookChain(RG_PlayerBlind, "@RG_PlayerBlind")
  RegisterHam(Ham_Touch, "player", "@on_touch_player")
  register_message(get_user_msgid("DeathMsg"), "@DeathMsg")

  bind_pcvar_num(
    create_cvar(
      "hns_airblock_return", "1", FCVAR_NONE,
      "0 - disable player returns, 1 - enable player returns",
      true, 0.0, true, 1.0
    ),
    airblock_return
  )

  bind_pcvar_float(
    create_cvar(
      "hns_airblock_damage", "35.0", FCVAR_NONE,
      "Minimum fall damage required to return the player",
      true, 0.0
    ),
    airblock_damage
  )

  bind_pcvar_num(
    create_cvar(
      "hns_airblock_chat", "2", FCVAR_NONE,
      "0 - disabled, 1 - only successful returns, 2 - all detected air blocks",
      true, 0.0, true, 2.0
    ),
    airblock_chat
  )

  bind_pcvar_num(
    create_cvar(
      "hns_airblock_killfeed", "1", FCVAR_NONE,
      "0 - disabled, 1 - show blocker or flasher in the kill feed",
      true, 0.0, true, 1.0
    ),
    airblock_killfeed
  )

  for (new i = 1; i <= get_maxplayers(); i++) {
    player_origin[i] = ArrayCreate(3);
    player_angles[i] = ArrayCreate(3);
  }
}

public plugin_cfg() {
  hns_get_prefix(prefix, charsmax(prefix))
}

public client_disconnected(id) {
  ArrayClear(player_origin[id])
  ArrayClear(player_angles[id])
  arrayset(player[id], 0, Player)
}

public plugin_end() {
  for (new i = 1; i <= get_maxplayers(); i++) {
    if (player_origin[i] != Invalid_Array) {
      ArrayDestroy(player_origin[i])
      player_origin[i] = Invalid_Array
    }

    if (player_angles[i] != Invalid_Array) {
      ArrayDestroy(player_angles[i])
      player_angles[i] = Invalid_Array
    }
  }
}

@RG_CSGameRules_FlPlayerFallDamage(const id) {
  if (!is_airblock_notify_mode() || !is_user_alive(id))
    return HC_CONTINUE

  new const Float: damage = Float: GetHookChainReturn(ATYPE_FLOAT)
  if (damage <= 0.0) return HC_CONTINUE

  new bool: is_player_block = player[id][is_touched] && is_user_connected(player[id][toucher])
  new bool: is_air_flash = player[id][is_full_flashed] && is_user_connected(player[id][flasher])
  if (!is_player_block && !is_air_flash)
    return HC_CONTINUE

  new bool: should_return = airblock_return
    && is_block_return_mode()
    && damage >= airblock_damage

  if (damage >= 1.0
      && hns_get_mode() != MODE_TRAINING
      && (airblock_chat == 2 || (airblock_chat == 1 && should_return))) {
    new damage_num = floatround(damage)

    if (is_player_block) {
      client_print_color(0, print_team_blue, "%s Player ^3%n^1 blocked player ^3%n^1 (^3%d^1 fall damage).",
                        prefix, player[id][toucher], id, damage_num)
    } else {
      client_print_color(0, print_team_blue, "%s Player ^3%n^1 Air Flashed ^3%n^1 (^3%d^1 fall damage).",
                        prefix, player[id][flasher], id, damage_num)
    }
  }

  if (airblock_killfeed && !should_return && damage >= get_entvar(id, var_health)) {
    player[id][killfeed_actor] = is_player_block ? player[id][toucher] : player[id][flasher]
    player[id][killfeed_type] = is_player_block ? KILLFEED_BLOCK : KILLFEED_FLASH
  } else {
    reset_killfeed_state(id)
  }

  player[id][is_touched] = false
  player[id][is_full_flashed] = false
  player[id][toucher] = 0
  player[id][flasher] = 0

  if (!should_return)
    return HC_CONTINUE

  player[id][is_blocked] = true

  SetHookChainReturn(ATYPE_FLOAT, 0.0)
  return HC_SUPERCEDE
}

@RG_PlayerBlind(const id, inflictor, attacker, Float:fade_time, Float:fade_hold, alpha, Float:color[3]) {
  if (!is_airblock_notify_mode() || !is_user_alive(id))
    return HC_CONTINUE

  if (get_member(id, m_iTeam) != TEAM_CT
      || !is_user_connected(attacker)
      || get_member(attacker, m_iTeam) != TEAM_TERRORIST
      || id == attacker
      || alpha != 255
      || fade_hold < 1.0)
    return HC_CONTINUE

  if (get_entvar(id, var_flags) & FL_ONGROUND || get_entvar(id, var_movetype) == MOVETYPE_FLY)
    return HC_CONTINUE

  player[id][is_full_flashed] = true
  player[id][flasher] = attacker
  return HC_CONTINUE
}

@RG_CBasePlayer_PreThink(const id) {
  if (!is_airblock_notify_mode()) {
    reset_player_state(id)
    return HC_CONTINUE
  }

  if (!is_user_alive(id)) {
    reset_player_state(id)
    return HC_CONTINUE
  }

  reset_killfeed_state(id)

  static Float: origin[3], Float: angles[3]

  if (player[id][is_blocked] && (!airblock_return || !is_block_return_mode())) {
    reset_player_state(id)
    return HC_CONTINUE
  }

  if (!airblock_return || !is_block_return_mode()) {
    reset_player_trajectory(id)

    if (get_entvar(id, var_flags) & FL_ONGROUND || get_entvar(id, var_movetype) == MOVETYPE_FLY) {
      if (player[id][last_frames] > 10) {
        player[id][is_touched] = false
        player[id][is_full_flashed] = false
        player[id][toucher] = 0
        player[id][flasher] = 0
        player[id][last_frames] = 0
      } else {
        player[id][last_frames]++
      }
    }

    return HC_CONTINUE
  }

  if (player[id][is_blocked]) {
    new const length = ArraySize(player_origin[id]) - 1
    if (length >= 0) {
      ArrayGetArray(player_origin[id], length, origin)
      ArrayGetArray(player_angles[id], length, angles)

      ArrayDeleteItem(player_origin[id], length)
      ArrayDeleteItem(player_angles[id], length)

      set_entvar(id, var_velocity, Float: {0.0, 0.0, 0.0})
      set_entvar(id, var_flags, get_entvar(id, var_flags) | FL_DUCKING)
      set_entvar(id, var_origin, origin)
      set_entvar(id, var_angles, angles)
      set_entvar(id, var_fixangle, 1)
    } else {
      player[id][is_blocked] = false
    }

    return HC_CONTINUE
  }

  get_entvar(id, var_origin, origin)
  get_entvar(id, var_v_angle, angles)

  if (get_entvar(id, var_flags) & FL_ONGROUND || get_entvar(id, var_movetype) == MOVETYPE_FLY) {
    if (player[id][last_frames] > 10) {
      player[id][is_touched] = false
      player[id][is_full_flashed] = false
      player[id][flasher] = 0
      ArrayClear(player_origin[id])
      ArrayClear(player_angles[id])
      player[id][last_frames] = 0
    } else {
      ArrayPushArray(player_origin[id], origin)
      ArrayPushArray(player_angles[id], angles)
      player[id][last_frames]++
    }
  } else {
    ArrayPushArray(player_origin[id], origin)
    ArrayPushArray(player_angles[id], angles)
  }

  return HC_CONTINUE
}

@DeathMsg() {
  new const victim = get_msg_arg_int(2)
  if (victim < 1 || victim > MAX_PLAYERS)
    return PLUGIN_CONTINUE

  new const original_killer = get_msg_arg_int(1)
  new const actor = player[victim][killfeed_actor]
  new const type = player[victim][killfeed_type]
  reset_killfeed_state(victim)

  if (!airblock_killfeed
      || type == KILLFEED_NONE
      || (original_killer != 0 && original_killer != victim)
      || !is_user_connected(actor))
    return PLUGIN_CONTINUE

  set_msg_arg_int(1, ARG_BYTE, actor)
  set_msg_arg_int(3, ARG_BYTE, 0)
  set_msg_arg_string(4, type == KILLFEED_FLASH ? "flashbang" : "tracktrain")
  return PLUGIN_CONTINUE
}

@on_touch_player(const id, const entity) {
  if (!is_airblock_notify_mode()) return HAM_IGNORED
  if (!is_user_valid(id) || !is_user_valid(entity)) return HAM_IGNORED
  if (get_member(id, m_iTeam) != TEAM_CT) return HAM_IGNORED
  if (rg_player_relationship(id, entity) != GR_NOTTEAMMATE) return HAM_IGNORED

  new Float:velocity[3]
  get_entvar(id, var_velocity, velocity)

  if (velocity[2] != 0.0) {
    player[id][is_touched] = true
    player[id][toucher] = entity
  }

  return HAM_IGNORED
}

stock is_user_valid(const id) {
  return is_entity(id) && is_user_connected(id) && !is_user_bot(id) && !is_user_hltv(id)
}

stock bool:is_block_return_mode() {
  new HNS_MODES: mode = hns_get_mode()
  return mode == MODE_PUB || mode == MODE_DM || mode == MODE_DM_1TT
}

stock bool:is_airblock_notify_mode() {
  new HNS_MODES: mode = hns_get_mode()
  return mode == MODE_PUB || mode == MODE_DM || mode == MODE_DM_1TT || mode == MODE_MIX
}

stock reset_player_state(const id) {
  reset_player_trajectory(id)
  arrayset(player[id], 0, Player)
}

stock reset_player_trajectory(const id) {
  if (player_origin[id] != Invalid_Array)
    ArrayClear(player_origin[id])

  if (player_angles[id] != Invalid_Array)
    ArrayClear(player_angles[id])
}

stock reset_killfeed_state(const id) {
  player[id][killfeed_actor] = 0
  player[id][killfeed_type] = KILLFEED_NONE
}
