#include "script_component.hpp"
/*
 * Author: nkenny
 * Group leadership handler -- leads to profiles, assessments, contact state and other responses
 *
 * Arguments:
 * 0: group leader <OBJECT>
 * 1: known enemy <OBJECT>
 *
 * Return Value:
 * bool
 *
 * Example:
 * [bob, angryJoe] call lambs_danger_fnc_tactics;
 *
 * Public: No
 *
 * ===========================================================================
 * NE BULACAKSIN — BOUNDING DEVRALMA KONTROLU
 * ===========================================================================
 *
 * Bu dosya artik bounding icin "kapi bekcisi" gorevi gorur.
 * Asagidaki kosullar SAGLANDIGINDA bounding tetiklenir:
 *
 *   [1] _target null degil
 *   [2] Grupta >= 4 birlik var
 *   [3] Hedef 25m'den uzak
 *   [4] Hedef 200m'den yakin
 *   [5] %85 sans (random)  <- %50'den yukseltildi
 *   [6] isBounding == false
 *
 * NOT: isExecutingTactic kontrolu KALDIRILDI. Bounding oncelikli taktiktir.
 *      Eski taktik flag'leri bounding baslarken temizlenir.
 *
 * ===========================================================================
*/
params [["_unit", objNull, [objNull]], ["_target", objNull, [objNull]]];

private _group = group _unit;

if (EGVAR(main,debug_functions)) then {
    diag_log format ["[TACTICS-CAGRI] unit: %1 | target: %2 | contact: %3", _unit, _target, _group getVariable ["lambs_danger_contact", 0]];
};

// CQB mode ~ disabled awaiting polish ~ nkenny
//if (formation _unit in GVAR(cqb_formations)) exitWith {
//    _unit call FUNC(tacticsCQB);
//};

// check if group AI disabled
if (_group getVariable [QGVAR(disableGroupAI), false]) exitWith {false};

// Initated contact?
private _contactState = _group getVariable [QGVAR(contact), 0];
if (_contactState < time) exitWith {[_unit, _target] call FUNC(contact)};

// KILIT KURTARMA: isBounding 120 sn'den eskiyse sifirla
private _bndTime = _group getVariable [QGVAR(boundingStartTime), 0];
if (_group getVariable [QGVAR(isBounding), false] && {time - _bndTime > 120}) then {
    if (EGVAR(main,debug_functions)) then {
        diag_log format ["[BND] KILIT KURTARMA: %1 (120 sn asildi)", _group];
    };
    _group setVariable [QGVAR(isBounding), nil];
    _group setVariable [QGVAR(isExecutingTactic), nil];
};

// ---------------------------------------------------------------------------
// ELITE: Basit+ Bounding Overwatch devralma
// Kosullar: >= 4 birlik, hedef 25-200m arasinda, %85 sans
// isExecutingTactic kontrolu KALDIRILDI (bounding oncelikli)
// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// ELITE: KOMUTAN BEYNI — 5 faktor tehdit analizi + NATO karar tablosu
// Eski "random 1 < 0.85" zar atma KALDIRILDI.
// Karar fnc_commanderAssess.sqf'te verilir, burada sadece dispatch.
// ---------------------------------------------------------------------------
if (
    !isNull _target
    && {count (units _group) >= 4}
    && {!(_group getVariable [QGVAR(isBounding), false])}
    && {!(_group getVariable [QGVAR(isExecutingTactic), false])}
) exitWith {
    // Onceki taktik kilitlerini temizle
    _group setVariable [QGVAR(isExecutingTactic), nil];

    private _karar = [_group, _target] call FUNC(commanderAssess);

        switch (_karar) do {
        case "WITHDRAW": {
            [_group, _target] call FUNC(tacticsRetreat);
        };
                case "PEEL": {
            // Peel gecici olarak Retreat'e yonlendirildi
            // (Peel dosyasi korunuyor, ileride geri acilabilir)
            [_group, _target] call FUNC(tacticsRetreat);
        };
        case "HOLD": {
            _group setVariable [QGVAR(isExecutingTactic), true];
            [_group, _target] call FUNC(tacticsHold);
            [_group, 20] spawn {
                params ["_g", "_sure"];
                sleep _sure;
                if (!isNull _g) then { _g setVariable [QGVAR(isExecutingTactic), nil]; };
            };
        };
        case "DELAY": {
            _group setVariable [QGVAR(isExecutingTactic), true];
            [_group, _target] call FUNC(tacticsHide);
            [_group, 25] spawn {
                params ["_g", "_sure"];
                sleep _sure;
                if (!isNull _g) then { _g setVariable [QGVAR(isExecutingTactic), nil]; };
            };
        };
        case "SUPPRESS_ASSAULT": {
            [_group, _target] call FUNC(tacticsSuppress);
            [{
                params ["_g", "_t"];
                if (!isNull _g && {(units _g) isNotEqualTo []}) then {
                    [_g, _t] call FUNC(tacticsAssault);
                };
            }, [_group, _target], 4] call CBA_fnc_waitAndExecute;
        };
        case "FLANK": {
            [_group, _target] call FUNC(tacticsFlank);
        };
        case "ASSAULT": {
            [_group, _target] call FUNC(tacticsAssault);
        };
        default {
            [_group, _target] call FUNC(tacticsBounding);
        };
    };
    

    true
};

// ai profiles ~ here is where AI profiles will be extrapolated - nkenny
// if (_unit call FUNC(tacticsProfiles)) exitWith {true};

// Leader assessment
if (!isPlayer (leader _unit)) then {_unit call FUNC(tacticsAssess);};

// end
true