#include <amxmodx>
#include <reapi>
#include <hns_matchsystem>

new g_iMaxPlayers;

#define IsPlayer(%1) (1 <= (%1) <= g_iMaxPlayers)

public plugin_init() {
    register_plugin("HNS: Anti stop stub", "1.0", "OpenHNS");

    g_iMaxPlayers = get_maxplayers();

    RegisterHookChain(RG_CBasePlayer_TakeDamage, "CBasePlayer_TakeDamage_SlowDown", .post = true);
}

public CBasePlayer_TakeDamage_SlowDown(const this, pevInflictor, pevAttacker, Float:flDamage, bitsDamageType) {
    if (hns_get_mode() != MODE_PUB && hns_get_mode() != MODE_DM && hns_get_mode() != MODE_ZM && hns_get_mode() != MODE_DM_1TT) {
         return HC_CONTINUE;
    }

    if (!IsPlayer(pevAttacker) || this == pevAttacker) {
        return HC_CONTINUE;
    }

    if (GetHookChainReturn(ATYPE_INTEGER) && is_user_alive(this)) {
        set_member(this, m_flVelocityModifier, 1.0);
    }

    return HC_CONTINUE;
}