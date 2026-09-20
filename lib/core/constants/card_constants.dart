import 'dart:math';

import '../../models/ally.dart';
import '../../models/player.dart' show Faction;
import '../../models/armor.dart';
import '../../models/weapon.dart';
import 'enums.dart';

/// Deck de cartes issu du fichier « Données cartes.xlsx » (référence des
/// données — Sprint 4). Tirages uniformes par CARTE, pondérés par la
/// colonne « Nombre de cartes » de l'Excel.
///
/// Note (07/09/2026) : healers Dark Sion et Mère Talzin corrigés en Sith
/// (anomalie de l'Excel : 4 Empire / 0 Sith).
class CardConstants {
  CardConstants._();

  /// Tirage uniforme pondéré dans une liste [counts].
  static int _pick(Random rng, List<int> counts) {
    int roll =
        rng.nextInt(counts.fold(0, (int total, int count) => total + count));
    for (int i = 0; i < counts.length; i++) {
      roll -= counts[i];
      if (roll < 0) return i;
    }
    throw StateError('Tirage hors deck');
  }

  // --- Healers (8) : soin après combat + soin instantané au recrutement ---
  static final List<Ally> healers = [
    Ally.healer(
        name: 'Droïde médical',
        faction: Faction.empire,
        rarity: Rarity.rare,
        cost: 3,
        healAfter: 50,
        healInstant: 500),
    Ally.healer(
        name: 'Médic Trooper',
        faction: Faction.empire,
        rarity: Rarity.commun,
        cost: 2,
        healAfter: 25,
        healInstant: 250),
    Ally.healer(
        name: 'Stass Allie',
        faction: Faction.jedi,
        rarity: Rarity.commun,
        cost: 2,
        healAfter: 25,
        healInstant: 250),
    Ally.healer(
        name: 'Barriss Offee',
        faction: Faction.jedi,
        rarity: Rarity.rare,
        cost: 3,
        healAfter: 50,
        healInstant: 500),
    Ally.healer(
        name: 'Hera Syndulla',
        faction: Faction.rebel,
        rarity: Rarity.commun,
        cost: 2,
        healAfter: 25,
        healInstant: 250),
    Ally.healer(
        name: 'R2-D2',
        faction: Faction.rebel,
        rarity: Rarity.rare,
        cost: 3,
        healAfter: 50,
        healInstant: 500),
    Ally.healer(
        name: 'Dark Sion',
        faction: Faction.sith,
        rarity: Rarity.commun,
        cost: 2,
        healAfter: 25,
        healInstant: 250),
    Ally.healer(
        name: 'Mère Talzin',
        faction: Faction.sith,
        rarity: Rarity.rare,
        cost: 3,
        healAfter: 50,
        healInstant: 500),
  ];

  // --- Tanks (12) : bonus PV passifs ou dégâts subis divisés par 2 ---
  static final List<Ally> tanks = [
    Ally.tank(
        name: 'Savage Opress',
        faction: Faction.sith,
        rarity: Rarity.commun,
        cost: 2,
        hpBonus: 500),
    Ally.tank(
        name: 'Dark Malgus',
        faction: Faction.sith,
        rarity: Rarity.epique,
        cost: 4,
        dividesDamage: true),
    Ally.tank(
        name: 'Dark Trooper',
        faction: Faction.empire,
        rarity: Rarity.commun,
        cost: 2,
        hpBonus: 500),
    Ally.tank(
        name: 'Garde Royal',
        faction: Faction.empire,
        rarity: Rarity.rare,
        cost: 3,
        hpBonus: 1000),
    Ally.tank(
        name: 'Captain Phasma',
        faction: Faction.empire,
        rarity: Rarity.epique,
        cost: 4,
        dividesDamage: true),
    Ally.tank(
        name: 'Kit Fisto',
        faction: Faction.jedi,
        rarity: Rarity.commun,
        cost: 2,
        hpBonus: 500),
    Ally.tank(
        name: 'Plo Koon',
        faction: Faction.jedi,
        rarity: Rarity.rare,
        cost: 3,
        hpBonus: 1000),
    Ally.tank(
        name: 'Dark Bane',
        faction: Faction.sith,
        rarity: Rarity.rare,
        cost: 3,
        hpBonus: 1000),
    Ally.tank(
        name: 'Mace Windu',
        faction: Faction.jedi,
        rarity: Rarity.epique,
        cost: 5,
        dividesDamage: true),
    Ally.tank(
        name: 'Baze Malbus',
        faction: Faction.rebel,
        rarity: Rarity.commun,
        cost: 2,
        hpBonus: 500),
    Ally.tank(
        name: 'Saw Gerrera',
        faction: Faction.rebel,
        rarity: Rarity.rare,
        cost: 3,
        hpBonus: 1000),
    Ally.tank(
        name: 'Chewbacca',
        faction: Faction.rebel,
        rarity: Rarity.epique,
        cost: 4,
        dividesDamage: true),
  ];

  // --- Nukers (32) : bonus/dégâts par faction (données stockées, effets
  // activés plus tard — monstres neutres, utile en JvJ) ---
  static final List<Ally> nukers = [
    Ally.nuker(
        name: 'Snowtrooper',
        faction: Faction.empire,
        rarity: Rarity.commun,
        cost: 2,
        dmgVsJedi: -50,
        dmgVsRebel: -100,
        bonusIfSithOwner: 100,
        bonusIfEmpireOwner: 200),
    Ally.nuker(
        name: 'Bossk',
        faction: Faction.empire,
        rarity: Rarity.commun,
        cost: 2,
        dmgVsJedi: -50,
        dmgVsRebel: -100,
        bonusIfSithOwner: 100,
        bonusIfEmpireOwner: 200),
    Ally.nuker(
        name: 'Cad Bane',
        faction: Faction.empire,
        rarity: Rarity.commun,
        cost: 2,
        dmgVsJedi: -50,
        dmgVsRebel: -100,
        bonusIfSithOwner: 100,
        bonusIfEmpireOwner: 200),
    Ally.nuker(
        name: 'Scout Trooper',
        faction: Faction.empire,
        rarity: Rarity.commun,
        cost: 2,
        dmgVsJedi: -50,
        dmgVsRebel: -100,
        bonusIfSithOwner: 100,
        bonusIfEmpireOwner: 200),
    Ally.nuker(
        name: 'Greedo',
        faction: Faction.empire,
        rarity: Rarity.rare,
        cost: 3,
        dmgVsJedi: -100,
        dmgVsRebel: -250,
        bonusIfSithOwner: 250,
        bonusIfEmpireOwner: 500),
    Ally.nuker(
        name: 'IG-88',
        faction: Faction.empire,
        rarity: Rarity.rare,
        cost: 3,
        dmgVsJedi: -100,
        dmgVsRebel: -250,
        bonusIfSithOwner: 250,
        bonusIfEmpireOwner: 500),
    Ally.nuker(
        name: 'Jango Fett',
        faction: Faction.empire,
        rarity: Rarity.epique,
        cost: 4,
        dmgVsJedi: -250,
        dmgVsRebel: -500,
        bonusIfSithOwner: 500,
        bonusIfEmpireOwner: 1000),
    Ally.nuker(
        name: 'Boba Fett',
        faction: Faction.empire,
        rarity: Rarity.epique,
        cost: 4,
        dmgVsJedi: -250,
        dmgVsRebel: -500,
        bonusIfSithOwner: 500,
        bonusIfEmpireOwner: 1000),
    Ally.nuker(
        name: 'Général Grievous',
        faction: Faction.sith,
        rarity: Rarity.epique,
        cost: 4,
        dmgVsJedi: -500,
        dmgVsRebel: -250,
        bonusIfSithOwner: 1000,
        bonusIfEmpireOwner: 500),
    Ally.nuker(
        name: 'Dark Maul',
        faction: Faction.sith,
        rarity: Rarity.epique,
        cost: 4,
        dmgVsJedi: -500,
        dmgVsRebel: -250,
        bonusIfSithOwner: 1000,
        bonusIfEmpireOwner: 500),
    Ally.nuker(
        name: 'Grand Inquisiteur',
        faction: Faction.sith,
        rarity: Rarity.commun,
        cost: 2,
        dmgVsJedi: -100,
        dmgVsRebel: -50,
        bonusIfSithOwner: 200,
        bonusIfEmpireOwner: 100),
    Ally.nuker(
        name: 'Dark Talon',
        faction: Faction.sith,
        rarity: Rarity.commun,
        cost: 2,
        dmgVsJedi: -100,
        dmgVsRebel: -50,
        bonusIfSithOwner: 200,
        bonusIfEmpireOwner: 100),
    Ally.nuker(
        name: 'Comte Dooku',
        faction: Faction.sith,
        rarity: Rarity.rare,
        cost: 3,
        dmgVsJedi: -250,
        dmgVsRebel: -100,
        bonusIfSithOwner: 500,
        bonusIfEmpireOwner: 250),
    Ally.nuker(
        name: 'Dark Revan',
        faction: Faction.sith,
        rarity: Rarity.rare,
        cost: 3,
        dmgVsJedi: -250,
        dmgVsRebel: -100,
        bonusIfSithOwner: 500,
        bonusIfEmpireOwner: 250),
    Ally.nuker(
        name: 'Asajj Ventress',
        faction: Faction.sith,
        rarity: Rarity.commun,
        cost: 2,
        dmgVsJedi: -100,
        dmgVsRebel: -50,
        bonusIfSithOwner: 200,
        bonusIfEmpireOwner: 100),
    Ally.nuker(
        name: 'Kylo Ren',
        faction: Faction.sith,
        rarity: Rarity.commun,
        cost: 2,
        dmgVsJedi: -100,
        dmgVsRebel: -50,
        bonusIfSithOwner: 200,
        bonusIfEmpireOwner: 100),
    Ally.nuker(
        name: 'Cassian Andor',
        faction: Faction.rebel,
        rarity: Rarity.commun,
        cost: 2,
        dmgVsJedi: 100,
        dmgVsRebel: 200,
        bonusIfSithOwner: -50,
        bonusIfEmpireOwner: -100),
    Ally.nuker(
        name: 'Jyn Erso',
        faction: Faction.rebel,
        rarity: Rarity.commun,
        cost: 2,
        dmgVsJedi: 100,
        dmgVsRebel: 200,
        bonusIfSithOwner: -50,
        bonusIfEmpireOwner: -100),
    Ally.nuker(
        name: 'Finn',
        faction: Faction.rebel,
        rarity: Rarity.commun,
        cost: 2,
        dmgVsJedi: 100,
        dmgVsRebel: 200,
        bonusIfSithOwner: -50,
        bonusIfEmpireOwner: -100),
    Ally.nuker(
        name: 'Poe Dameron',
        faction: Faction.rebel,
        rarity: Rarity.commun,
        cost: 2,
        dmgVsJedi: 100,
        dmgVsRebel: 200,
        bonusIfSithOwner: -50,
        bonusIfEmpireOwner: -100),
    Ally.nuker(
        name: 'Biggs Darklighter',
        faction: Faction.rebel,
        rarity: Rarity.rare,
        cost: 3,
        dmgVsJedi: 250,
        dmgVsRebel: 500,
        bonusIfSithOwner: -100,
        bonusIfEmpireOwner: -250),
    Ally.nuker(
        name: 'Wedge Antilles',
        faction: Faction.rebel,
        rarity: Rarity.rare,
        cost: 3,
        dmgVsJedi: 250,
        dmgVsRebel: 500,
        bonusIfSithOwner: -100,
        bonusIfEmpireOwner: -250),
    Ally.nuker(
        name: 'Lando Calrissian',
        faction: Faction.rebel,
        rarity: Rarity.epique,
        cost: 4,
        dmgVsJedi: 500,
        dmgVsRebel: 1000,
        bonusIfSithOwner: -250,
        bonusIfEmpireOwner: -500),
    Ally.nuker(
        name: 'Han Solo',
        faction: Faction.rebel,
        rarity: Rarity.epique,
        cost: 4,
        dmgVsJedi: 500,
        dmgVsRebel: 1000,
        bonusIfSithOwner: -250,
        bonusIfEmpireOwner: -500),
    Ally.nuker(
        name: 'Galen Marek',
        faction: Faction.jedi,
        rarity: Rarity.commun,
        cost: 2,
        dmgVsJedi: 200,
        dmgVsRebel: 100,
        bonusIfSithOwner: -100,
        bonusIfEmpireOwner: -50),
    Ally.nuker(
        name: 'Yarael Poof',
        faction: Faction.jedi,
        rarity: Rarity.commun,
        cost: 2,
        dmgVsJedi: 200,
        dmgVsRebel: 100,
        bonusIfSithOwner: -100,
        bonusIfEmpireOwner: -50),
    Ally.nuker(
        name: 'Aayla Secura',
        faction: Faction.jedi,
        rarity: Rarity.commun,
        cost: 2,
        dmgVsJedi: 200,
        dmgVsRebel: 100,
        bonusIfSithOwner: -100,
        bonusIfEmpireOwner: -50),
    Ally.nuker(
        name: 'Shaak Ti',
        faction: Faction.jedi,
        rarity: Rarity.commun,
        cost: 2,
        dmgVsJedi: 200,
        dmgVsRebel: 100,
        bonusIfSithOwner: -100,
        bonusIfEmpireOwner: -50),
    Ally.nuker(
        name: 'Qui-Gon Jinn',
        faction: Faction.jedi,
        rarity: Rarity.rare,
        cost: 3,
        dmgVsJedi: 500,
        dmgVsRebel: 250,
        bonusIfSithOwner: -250,
        bonusIfEmpireOwner: -100),
    Ally.nuker(
        name: 'Rey',
        faction: Faction.jedi,
        rarity: Rarity.rare,
        cost: 3,
        dmgVsJedi: 500,
        dmgVsRebel: 250,
        bonusIfSithOwner: -250,
        bonusIfEmpireOwner: -100),
    Ally.nuker(
        name: 'Obi-Wan Kenobi',
        faction: Faction.jedi,
        rarity: Rarity.epique,
        cost: 4,
        dmgVsJedi: 1000,
        dmgVsRebel: 500,
        bonusIfSithOwner: -500,
        bonusIfEmpireOwner: -250),
    Ally.nuker(
        name: 'Anakin Skywalker',
        faction: Faction.jedi,
        rarity: Rarity.epique,
        cost: 4,
        dmgVsJedi: 1000,
        dmgVsRebel: 500,
        bonusIfSithOwner: -500,
        bonusIfEmpireOwner: -250),
  ];

  // --- Escouades (4 types × 10 cartes) : bonus ATK cumulatif par copie
  // (+50 propre / +25 alliée), dégâts instantanés stockés ---
  static final List<Ally> squads = [
    Ally.squad(
        name: 'Stormtrooper',
        faction: Faction.empire,
        count: 10,
        bonusOwn: 50,
        bonusAllied: 25,
        instantDamage1: -10,
        instantDamage2: -25),
    Ally.squad(
        name: 'Ewok',
        faction: Faction.rebel,
        count: 10,
        bonusOwn: 50,
        bonusAllied: 25,
        instantDamage1: -10,
        instantDamage2: -25),
    Ally.squad(
        name: 'Sith Trooper',
        faction: Faction.sith,
        count: 10,
        bonusOwn: 50,
        bonusAllied: 25,
        instantDamage1: -25,
        instantDamage2: -10),
    Ally.squad(
        name: 'Padawan',
        faction: Faction.jedi,
        count: 10,
        bonusOwn: 50,
        bonusAllied: 25,
        instantDamage1: -25,
        instantDamage2: -10),
  ];

  // --- Soutiens (20) : capacités stockées (effets actifs plus tard) ---
  static final List<Ally> supports = [
    Ally.support(
        name: 'Adi Gallia',
        faction: Faction.jedi,
        rarity: Rarity.commun,
        cost: 2,
        ability: 'preventDeath',
        effectText:
            'Une seule fois : empêche la mort et garde le perso à 1 PV'),
    Ally.support(
        name: 'Jocasta Nu',
        faction: Faction.jedi,
        rarity: Rarity.commun,
        cost: 2,
        ability: 'bonusXp20',
        effectText: '+20 XP en plus après chaque combat'),
    Ally.support(
        name: 'Ki-Adi-Mundi',
        faction: Faction.jedi,
        rarity: Rarity.rare,
        cost: 3,
        ability: 'critOn5',
        effectText: 'Le 5 compte aussi pour un coup critique'),
    Ally.support(
        name: 'Luminara Unduli',
        faction: Faction.jedi,
        rarity: Rarity.rare,
        cost: 3,
        ability: 'doubleMoveDice',
        effectText: 'Multipliez la valeur du dé par deux pour vous déplacer'),
    Ally.support(
        name: 'Yaddle',
        faction: Faction.jedi,
        rarity: Rarity.epique,
        cost: 4,
        ability: 'attackTimesDice',
        effectText:
            'Une seule fois : lancez le dé et multipliez l\'attaque par le chiffre du dé'),
    Ally.support(
        name: 'Mon Mothma',
        faction: Faction.rebel,
        rarity: Rarity.commun,
        cost: 2,
        ability: 'preventDeath',
        effectText:
            'Une seule fois : empêche la mort et garde le perso à 1 PV'),
    Ally.support(
        name: 'Chirrut Îmwe',
        faction: Faction.rebel,
        rarity: Rarity.commun,
        cost: 2,
        ability: 'bonusXp20',
        effectText: '+20 XP en plus après chaque combat'),
    Ally.support(
        name: 'Bail Organa',
        faction: Faction.rebel,
        rarity: Rarity.rare,
        cost: 3,
        ability: 'doubleMoveDice',
        effectText: 'Multipliez la valeur du dé par deux pour vous déplacer'),
    Ally.support(
        name: 'C-3PO',
        faction: Faction.rebel,
        rarity: Rarity.rare,
        cost: 3,
        ability: 'critOn5',
        effectText: 'Le 5 compte aussi pour un coup critique'),
    Ally.support(
        name: 'Amiral Ackbar',
        faction: Faction.rebel,
        rarity: Rarity.epique,
        cost: 4,
        ability: 'attackTimesDice',
        effectText:
            'Une seule fois : lancez le dé et multipliez l\'attaque par le chiffre du dé'),
    Ally.support(
        name: 'Dark Malak',
        faction: Faction.sith,
        rarity: Rarity.commun,
        cost: 2,
        ability: 'bonusXp20',
        effectText: '+20 XP en plus après chaque combat'),
    Ally.support(
        name: 'Dark Traya',
        faction: Faction.sith,
        rarity: Rarity.commun,
        cost: 2,
        ability: 'preventDeath',
        effectText:
            'Une seule fois : empêche la mort et garde le perso à 1 PV'),
    Ally.support(
        name: 'Snoke',
        faction: Faction.sith,
        rarity: Rarity.rare,
        cost: 3,
        ability: 'doubleMoveDice',
        effectText: 'Multipliez la valeur du dé par deux pour vous déplacer'),
    Ally.support(
        name: 'Dark Plagueis',
        faction: Faction.sith,
        rarity: Rarity.rare,
        cost: 3,
        ability: 'critOn5',
        effectText: 'Le 5 compte aussi pour un coup critique'),
    Ally.support(
        name: 'Dark Sidious',
        faction: Faction.sith,
        rarity: Rarity.epique,
        cost: 4,
        ability: 'attackTimesDice',
        effectText:
            'Une seule fois : lancez le dé et multipliez l\'attaque par le chiffre du dé'),
    Ally.support(
        name: 'Bib Fortuna',
        faction: Faction.empire,
        rarity: Rarity.commun,
        cost: 2,
        ability: 'bonusXp20',
        effectText: '+20 XP en plus après chaque combat'),
    Ally.support(
        name: 'Droïde impériale',
        faction: Faction.empire,
        rarity: Rarity.commun,
        cost: 2,
        ability: 'preventDeath',
        effectText:
            'Une seule fois : empêche la mort et garde le perso à 1 PV'),
    Ally.support(
        name: 'Nute Gunray',
        faction: Faction.empire,
        rarity: Rarity.rare,
        cost: 3,
        ability: 'critOn5',
        effectText: 'Le 5 compte aussi pour un coup critique'),
    Ally.support(
        name: 'Directeur Krennic',
        faction: Faction.empire,
        rarity: Rarity.rare,
        cost: 3,
        ability: 'doubleMoveDice',
        effectText: 'Multipliez la valeur du dé par deux pour vous déplacer'),
    Ally.support(
        name: 'Jabba le Hutt',
        faction: Faction.empire,
        rarity: Rarity.epique,
        cost: 4,
        ability: 'attackTimesDice',
        effectText:
            'Une seule fois : lancez le dé et multipliez l\'attaque par le chiffre du dé'),
  ];

  // --- Spéciales (8 légendaires) : bonus appliqués au porteur de faction
  // amie (propre ou alliée) ; faction ennemie = -500 PV, jamais recrutée.
  // Valeurs issues des effectText (Excel « Données cartes ») — 10/09/2026.
  static final List<Ally> specials = [
    Ally.special(
        name: 'Yoda',
        faction: Faction.jedi,
        bonusAtkIfFriendly: 1500,
        bonusHpIfFriendly: 1000,
        effectText:
            'Sith/Empire : -500 PV · Jedi/Rebel : +1500 ATK · Jedi/Rebel : +1000 PV'),
    Ally.special(
        name: 'Dark Vador',
        faction: Faction.empire,
        bonusAtkIfFriendly: 1500,
        bonusHpIfFriendly: 1000,
        effectText:
            'Jedi/Rebel : -500 PV · Sith/Empire : +1500 ATK · Sith/Empire : +1000 PV'),
    Ally.special(
        name: 'Princesse Leia',
        faction: Faction.rebel,
        bonusAtkIfFriendly: 2000,
        bonusHpIfFriendly: 500,
        effectText:
            'Sith/Empire : -500 PV · Jedi/Rebel : +2000 ATK · Jedi/Rebel : +500 PV'),
    Ally.special(
        name: 'Padmé Amidala',
        faction: Faction.rebel,
        bonusAtkIfFriendly: 1500,
        bonusHpIfFriendly: 1000,
        effectText:
            'Sith/Empire : -500 PV · Jedi/Rebel : +1500 ATK · Jedi/Rebel : +1000 PV'),
    Ally.special(
        name: 'Dark Nihilus',
        faction: Faction.sith,
        bonusAtkIfFriendly: 2000,
        bonusHpIfFriendly: 500,
        effectText:
            'Jedi/Rebel : -500 PV · Sith/Empire : +2000 ATK · Sith/Empire : +500 PV'),
    Ally.special(
        name: "L'empereur",
        faction: Faction.empire,
        bonusAtkIfFriendly: 2000,
        bonusHpIfFriendly: 500,
        effectText:
            'Jedi/Rebel : -500 PV · Sith/Empire : +2000 ATK · Sith/Empire : +500 PV'),
    Ally.special(
        name: 'Grand Moff Tarkin',
        faction: Faction.empire,
        bonusAtkIfFriendly: 1500,
        bonusHpIfFriendly: 1000,
        effectText:
            'Jedi/Rebel : -500 PV · Sith/Empire : +1500 ATK · Sith/Empire : +1000 PV'),
    Ally.special(
        name: 'Luke Skywalker',
        faction: Faction.jedi,
        bonusAtkIfFriendly: 2000,
        bonusHpIfFriendly: 500,
        effectText:
            'Sith/Empire : -500 PV · Jedi/Rebel : +2000 ATK · Jedi/Rebel : +500 PV'),
  ];

  // --- Armes (30 cartes) : le bonus suit la table de rareté du GDD ---
  static const List<Weapon> weapons = [
    Weapon(
        id: 'sabre_laser_dark_maul',
        name: 'Sabre laser de Dark Maul',
        rarity: Rarity.mythique,
        attackBonus: 1000),
    Weapon(
        id: 'sabre_kylo_ren',
        name: 'Sabre Laser de Kylo Ren',
        rarity: Rarity.legendaire,
        attackBonus: 500),
    Weapon(
        id: 'sabre_vador',
        name: 'Sabre Laser de Vador',
        rarity: Rarity.legendaire,
        attackBonus: 500),
    Weapon(
        id: 'sabre_luke',
        name: 'Sabre Laser de Luke',
        rarity: Rarity.legendaire,
        attackBonus: 500),
    Weapon(
        id: 'sabre_windu',
        name: 'Sabre Laser de Windu',
        rarity: Rarity.epique,
        attackBonus: 250),
    Weapon(
        id: 'sabre_laser',
        name: 'Sabre Laser',
        rarity: Rarity.epique,
        attackBonus: 250),
    Weapon(
        id: 'pistolet_blaster_s5',
        name: 'Pistolet Blaster S-5',
        rarity: Rarity.epique,
        attackBonus: 250),
    Weapon(
        id: 'sabre_laser_noir',
        name: 'Sabre laser noir',
        rarity: Rarity.epique,
        attackBonus: 250),
    Weapon(
        id: 'canon_blaster_z6',
        name: 'Canon blaster Z-6',
        rarity: Rarity.epique,
        attackBonus: 250),
    Weapon(
        id: 'pistolet_westar34',
        name: 'Pistolet Westar-34',
        rarity: Rarity.rare,
        attackBonus: 100),
    Weapon(
        id: 'electro_baton',
        name: 'Électro-bâton',
        rarity: Rarity.rare,
        attackBonus: 100),
    Weapon(
        id: 'lance_lim',
        name: 'Lance-lim',
        rarity: Rarity.rare,
        attackBonus: 100),
    Weapon(
        id: 'bowcaster',
        name: 'Bowcaster',
        rarity: Rarity.rare,
        attackBonus: 100),
    Weapon(
        id: 'fusil_disruptor_t7',
        name: 'Fusil disruptor T-7',
        rarity: Rarity.rare,
        attackBonus: 100),
    Weapon(
        id: 'fusil_amban',
        name: 'Fusil Amban',
        rarity: Rarity.rare,
        attackBonus: 100),
    Weapon(
        id: 'arc_blaster',
        name: 'Arc blaster',
        rarity: Rarity.rare,
        attackBonus: 100),
    Weapon(
        id: 'fusil_blaster_a280',
        name: 'Fusil blaster A280',
        rarity: Rarity.commun,
        attackBonus: 50),
    Weapon(
        id: 'blaster_dl44',
        name: 'Blaster DL-44',
        rarity: Rarity.commun,
        attackBonus: 50),
    Weapon(
        id: 'blaster_dh17',
        name: 'Blaster DH-17',
        rarity: Rarity.commun,
        attackBonus: 50),
    Weapon(
        id: 'blaster_e11',
        name: 'Blaster E-11',
        rarity: Rarity.commun,
        attackBonus: 50),
    Weapon(
        id: 'carabine_dc15',
        name: 'Carabine blaster DC-15',
        rarity: Rarity.commun,
        attackBonus: 50),
    Weapon(
        id: 'baton_electro_stun',
        name: 'Bâton électro-stun',
        rarity: Rarity.commun,
        attackBonus: 50),
    Weapon(
        id: 'pist_blaster_se14c',
        name: 'Pist. blaster SE-14C',
        rarity: Rarity.commun,
        attackBonus: 50),
  ];

  // --- Tenues (30 cartes) : le bonus suit la table de rareté du GDD ---
  static const List<Armor> armors = [
    Armor(
        id: 'armure_dark_vador',
        name: 'Armure de Dark Vador',
        rarity: Rarity.mythique,
        hpBonus: 2000),
    Armor(
        id: 'tenue_luke',
        name: 'Tenue de Luke',
        rarity: Rarity.legendaire,
        hpBonus: 1000),
    Armor(
        id: 'tenue_palpatine',
        name: 'Tenue de Palpatine',
        rarity: Rarity.legendaire,
        hpBonus: 1000),
    Armor(
        id: 'armure_jango_fett',
        name: 'Armure de Jango Fett',
        rarity: Rarity.legendaire,
        hpBonus: 1000),
    Armor(
        id: 'armure_boba_fett',
        name: 'Armure de Boba Fett',
        rarity: Rarity.epique,
        hpBonus: 500),
    Armor(
        id: 'tenue_officier_imperial',
        name: "Tenue d'officier impérial",
        rarity: Rarity.epique,
        hpBonus: 500),
    Armor(
        id: 'tenue_jedi',
        name: 'Tenue de Jedi',
        rarity: Rarity.epique,
        hpBonus: 500),
    Armor(
        id: 'armure_magnagardes',
        name: 'Armure des MagnaGardes',
        rarity: Rarity.epique,
        hpBonus: 500),
    Armor(
        id: 'tenue_princesse_leia',
        name: 'Tenue de Princesse Leia',
        rarity: Rarity.epique,
        hpBonus: 500),
    Armor(
        id: 'scout_trooper',
        name: 'Scout Trooper',
        rarity: Rarity.rare,
        hpBonus: 200),
    Armor(
        id: 'snowtrooper',
        name: 'Snowtrooper',
        rarity: Rarity.rare,
        hpBonus: 200),
    Armor(
        id: 'death_trooper',
        name: 'Death Trooper',
        rarity: Rarity.rare,
        hpBonus: 200),
    Armor(
        id: 'shoretrooper',
        name: 'Shoretrooper',
        rarity: Rarity.rare,
        hpBonus: 200),
    Armor(
        id: 'garde_reine_amidala',
        name: 'Garde de la Reine Amidala',
        rarity: Rarity.rare,
        hpBonus: 200),
    Armor(
        id: 'armure_mandalorienne',
        name: 'Armure mandalorienne',
        rarity: Rarity.rare,
        hpBonus: 200),
    Armor(
        id: 'garde_imperial',
        name: 'Garde impérial',
        rarity: Rarity.rare,
        hpBonus: 200),
    Armor(
        id: 'tenue_stormtrooper',
        name: 'Tenue de Stormtrooper',
        rarity: Rarity.commun,
        hpBonus: 100),
    Armor(
        id: 'uniforme_officier_imperial',
        name: "Uniforme d'officier impérial",
        rarity: Rarity.commun,
        hpBonus: 100),
    Armor(
        id: 'armure_clone_phase1',
        name: 'Armure de clone Phase I',
        rarity: Rarity.commun,
        hpBonus: 100),
    Armor(
        id: 'armure_clone_phase2',
        name: 'Armure de clone Phase II',
        rarity: Rarity.commun,
        hpBonus: 100),
    Armor(
        id: 'tenue_rebelle_endor',
        name: 'Tenue rebelle d\'Endor',
        rarity: Rarity.commun,
        hpBonus: 100),
    Armor(
        id: 'tenue_pilote_xwing',
        name: 'Tenue pilote rebelle X-Wing',
        rarity: Rarity.commun,
        hpBonus: 100),
    Armor(
        id: 'tenue_jawa',
        name: 'Tenue de Jawa',
        rarity: Rarity.commun,
        hpBonus: 100),
  ];

  /// Toutes les cartes alliés recrutables (120 cartes : escouades en 10
  /// exemplaires, spéciales incluses). Les spéciales d'une faction ENNEMIE
  /// frappent le joueur de -500 PV au lieu d'être recrutées (Sprint 4.3).
  static List<Ally> get recruitDeck => <Ally>[
        ...healers,
        ...tanks,
        ...nukers,
        for (final Ally squad in squads)
          for (int i = 0; i < squad.teamCost * 10; i++) squad,
        ...supports,
        ...specials,
      ];

  /// Tire un allié uniformément parmi les 120 cartes recrutables.
  static Ally randomAllyCard(Random rng) {
    final List<List<Ally>> groups = <List<Ally>>[
      healers,
      tanks,
      nukers,
      squads,
      supports,
      specials,
    ];
    final List<int> counts = <int>[
      healers.length,
      tanks.length,
      nukers.length,
      squads.fold(0, (int t, Ally a) => t + a.teamCost * 10),
      supports.length,
      specials.length,
    ];
    int index = _pick(rng, counts);
    if (index == 3) {
      // Escouades : tirage parmi les 40 cartes (10 par type).
      return squads[_pick(rng, <int>[10, 10, 10, 10])];
    }
    final List<Ally> group = groups[index];
    return group[_pick(rng, List<int>.filled(group.length, 1))];
  }

  /// Nombre de cartes pour une arme : les communs existent en 2 exemplaires.
  static int weaponCardCount(Weapon weapon) =>
      weapon.rarity == Rarity.commun ? 2 : 1;

  /// Nombre de cartes pour une tenue : les communes existent en 2 exemplaires.
  static int armorCardCount(Armor armor) =>
      armor.rarity == Rarity.commun ? 2 : 1;

  /// Total de cartes d'armes (30) et de tenues (30).
  static int get weaponTotalCards => weapons.fold(
      0, (int total, Weapon w) => total + weaponCardCount(w));
  static int get armorTotalCards => armors.fold(
      0, (int total, Armor a) => total + armorCardCount(a));

  /// Tire une arme uniformément parmi les 30 cartes (communs × 2).
  static Weapon randomWeaponCard(Random rng) => weapons[_pick(
      rng, weapons.map(weaponCardCount).toList(growable: false))];

  /// Tire une tenue uniformément parmi les 30 cartes (communes × 2).
  static Armor randomArmorCard(Random rng) =>
      armors[_pick(rng, armors.map(armorCardCount).toList(growable: false))];
}
