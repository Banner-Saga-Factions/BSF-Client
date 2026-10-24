package engine.mod
{
   /**
    * ModAiSides — NEW FILE (not in original decompile).
    *
    * Whether the offline computer also plays the PLAYER's side (BSF-Client #31, Wave 4a:
    * AI vs AI). Offline practice battles are mirror matches, so with this on, one brain can
    * play another head to head, and the match runner can tell a better brain from a worse
    * one (ModAiBrain holds which brain plays each side).
    *
    * Read as each turn starts (BattleStateNextTurn), so a change takes effect from the next
    * turn. Ignored in an online battle: there the player's side belongs to a person. The mod
    * bridge's "set_ai_sides" command changes it (ModBattleControl). Off by default, and it
    * lasts until it is set again or the game restarts.
    */
   public class ModAiSides
   {

      /** True while the computer plays the player's units as well as its own. */
      public static var playerSide:Boolean = false;

      public function ModAiSides()
      {
         super();
      }
   }
}
