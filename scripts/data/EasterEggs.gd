class_name EasterEggs
extends RefCounted
## EasterEggs — Frozen tables for the two "tell your DM" easter eggs.
##
## Both tables were generated once from a seeded shuffle and then pasted here verbatim: they are
## DATA, not something to recompute. Every player must see the same phrase for the same help page
## and the same party combination, so nothing in this file may be randomised at runtime and no
## entry should be reordered or edited casually — doing so changes a phrase somebody may already
## have written down.
##
## Creature and spell names come from the D&D 5e SRD (open content); deities are the usual
## multiverse pantheon the campaign already references (Daragat is a cleric of Lathander).

## One per help topic, index-matched to HelpPanel's topic order.
const HELP_HINTS: Array[String] = [
	"Cockatrice vigila el umbral",
	"Will-o'-Wisp aguarda tras la puerta",
	"Gelatinous Cube ha oído tus pasos",
	"Otyugh afila sus garras",
	"Ankheg bloquea la salida",
	"Treant usó sigilo",
	"Griffon no ha comido en días",
	"Gorgon tiende una emboscada",
	"Lich custodia el tesoro",
	"Manticore te espera acechante",
]

## One per possible 4-of-7 party, keyed by the comma-joined sorted character ids — the exact same
## key SaveManager.record_profile_completion() writes into completed_party_combos.
const PARTY_BLESSINGS := {
	"azafran,barbara,daragat,huguito": "Eldath lanzó Geas",
	"azafran,barbara,daragat,lulu": "Gond lanzó Meteor Swarm",
	"azafran,barbara,daragat,rosa": "Tiamat lanzó Slow",
	"azafran,barbara,daragat,solana": "Malar lanzó Thunderwave",
	"azafran,barbara,huguito,lulu": "Myrkul lanzó Plane Shift",
	"azafran,barbara,huguito,rosa": "Corellon lanzó Finger of Death",
	"azafran,barbara,huguito,solana": "Silvanus lanzó Magic Missile",
	"azafran,barbara,lulu,rosa": "Mystra lanzó Contagion",
	"azafran,barbara,lulu,solana": "Deneir lanzó Foresight",
	"azafran,barbara,rosa,solana": "Tymora lanzó Dominate Monster",
	"azafran,daragat,huguito,lulu": "Shar lanzó Reverse Gravity",
	"azafran,daragat,huguito,rosa": "Torm lanzó Polymorph",
	"azafran,daragat,huguito,solana": "Talos lanzó Confusion",
	"azafran,daragat,lulu,rosa": "Azuth lanzó Earthquake",
	"azafran,daragat,lulu,solana": "Oghma lanzó Gate",
	"azafran,daragat,rosa,solana": "Mask lanzó Feeblemind",
	"azafran,huguito,lulu,rosa": "Moradin lanzó Disintegrate",
	"azafran,huguito,lulu,solana": "Cyric lanzó Web",
	"azafran,huguito,rosa,solana": "Umberlee lanzó Time Stop",
	"azafran,lulu,rosa,solana": "Chauntea lanzó Wish",
	"barbara,daragat,huguito,lulu": "Savras lanzó Storm of Vengeance",
	"barbara,daragat,huguito,rosa": "Selûne lanzó Guiding Bolt",
	"barbara,daragat,huguito,solana": "Tyr lanzó Haste",
	"barbara,daragat,lulu,rosa": "Helm lanzó Symbol",
	"barbara,daragat,lulu,solana": "Lathander lanzó Resurrection",
	"barbara,daragat,rosa,solana": "Waukeen lanzó Fireball",
	"barbara,huguito,lulu,rosa": "Bahamut lanzó Harm",
	"barbara,huguito,lulu,solana": "Ilmater lanzó Shapechange",
	"barbara,huguito,rosa,solana": "Auril lanzó Mass Heal",
	"barbara,lulu,rosa,solana": "Lolth lanzó Astral Projection",
	"daragat,huguito,lulu,rosa": "Sune lanzó Sunburst",
	"daragat,huguito,lulu,solana": "Beshaba lanzó Power Word Kill",
	"daragat,huguito,rosa,solana": "Gruumsh lanzó Antimagic Field",
	"daragat,lulu,rosa,solana": "Kelemvor lanzó Blight",
	"huguito,lulu,rosa,solana": "Tempus lanzó Cloudkill",
}

## Hint for a help page; empty if the topic index has no entry (so adding a page can never crash
## the manual, it just shows no easter egg until a phrase is added here).
static func help_hint(topic_index: int) -> String:
	if topic_index < 0 or topic_index >= HELP_HINTS.size():
		return ""
	return HELP_HINTS[topic_index]

## Blessing for the party that just finished a run. Builds the key the same way SaveManager does
## (sorted ids, comma-joined) so the two can never disagree.
static func party_blessing(party: Array) -> String:
	var ids: Array = []
	for m in party:
		ids.append(str(m.get("id", "")))
	ids.sort()
	return str(PARTY_BLESSINGS.get(",".join(ids), ""))
