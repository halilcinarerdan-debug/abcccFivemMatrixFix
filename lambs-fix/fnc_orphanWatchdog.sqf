#include "script_component.hpp"
/*
 * Author: Cinar (ELITE fork)
 * Orphan Unit Watchdog — taktik disi tek basina kalan birimleri gruba geri toplar
 *
 * ===========================================================================
 * NE YAPAR
 * ===========================================================================
 * Her 8 sn'de tum gruplari tarar.
 * Bir birim:
 *   - Leader'dan 40m+ uzakta
 *   - VE aktif taktik yurutmuyor (Bounding/Peel/Retreat)
 *   - VE araçta degil, oyuncu degil
 *   - VE yakininda dusman yok
 * ise gruba geri cagrilir (doFollow + forceMove temizle + hiz normal)
 *
 * Sadece server'da calisir. Taktik aktifken dokunmaz.
 *
 * Arguments: None
 * Return Value: None
 * Public: No
 * ===========================================================================
*/

// Sadece server'da calissin
if (!isServer) exitWith {};

private _WATCHDOG_INTERVAL = 8;    // Tarama araligi (sn)
private _ORPHAN_DISTANCE   = 40;   // Leader'dan bu kadar uzaktaysa yetim say
private _ENEMY_CLOSE_RANGE = 150;  // Bu mesafede dusman varsa dokunma

[_WATCHDOG_INTERVAL, _ORPHAN_DISTANCE, _ENEMY_CLOSE_RANGE] spawn {
    params ["_WATCHDOG_INTERVAL", "_ORPHAN_DISTANCE", "_ENEMY_CLOSE_RANGE"];
    while {true} do {
        sleep _WATCHDOG_INTERVAL;

        {
            private _g = _x;

            // Bos/olu grup atla
            if (isNull _g) then { continue };
            if ((units _g) isEqualTo []) then { continue };

            // Leader kontrolu
            private _leader = leader _g;
            if (isNull _leader) then { continue };
            if (isPlayer _leader) then { continue };

            // Aktif taktik varsa dokunma
            private _taktikAktif =
                (_g getVariable [QGVAR(isBounding), false])
                || {_g getVariable [QGVAR(isPeeling), false]}
                || {_g getVariable [QGVAR(isRetreating), false]}
                || {_g getVariable [QGVAR(isExecutingTactic), false]};

            if (_taktikAktif) then { continue };

            // 2026-10-01 FIX: temas / taze komutan karari varken dokunma.
            // FLANK/ASSAULT/SUPPRESS bayrak koymuyor; birimler lider'dan 40m+ uzaklasinca
            // watchdog doFollow ile manevrayi eziyordu.
            if ((_g getVariable [QGVAR(contact), 0]) > time) then { continue };
            if ((time - (_g getVariable [QGVAR(cmdSonKararZaman), -999])) < 45) then { continue };

            // Birimleri tara
            private _leaderPos = getPosATL _leader;
            {
                private _birim = _x;

                // Olu / araçta / oyuncu atla
                if (!alive _birim) then { continue };
                if (!isNull objectParent _birim) then { continue };
                if (isPlayer _birim) then { continue };

                // Leader'dan uzak mi?
                private _mesafe = _birim distance2D _leaderPos;
                if (_mesafe < _ORPHAN_DISTANCE) then { continue };

                // Yakininda dusman var mi? (savasan birim dokunma)
                private _dusman = _birim findNearestEnemy _birim;
                if (!isNull _dusman && {(_birim distance2D _dusman) < _ENEMY_CLOSE_RANGE}) then { continue };

                // YETIM! Topla.
                _birim setVariable [QGVAR(forceMove), nil];
                _birim setVariable [QEGVAR(main,currentTask), nil, EGVAR(main,debug_functions)];
                _birim setUnitPos "AUTO";
                _birim forceSpeed -1;
                _birim doFollow _leader;

                if (EGVAR(main,debug_functions)) then {
                    diag_log format [
                        "[YETIM-TOPLA] %1 | birim:%2 | mesafe:%3m | grup:%4",
                        _g, name _birim, round _mesafe, groupId _g
                    ];
                };
            } forEach (units _g);
        } forEach allGroups;
    };
};

// end
true