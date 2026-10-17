package engine.mod
{
   /**
    * ModAiBrain — NEW FILE (not in original decompile).
    *
    * Which brain the offline computer opponent thinks with (BSF-Client #31, Wave 4):
    *
    *   dredge  the planner the game shipped with, plus our fixes (AiModuleDredge)
    *   search  the same planner, plus a one-move look-ahead: before it commits, it asks
    *           what the enemy who acts next could do back to it (AiModuleSearch)
    *
    * It is read each time a computer turn starts (BattleStateTurnAi), so a change takes
    * effect from the next computer turn. The mod bridge's "set_ai_brain" command changes
    * it (ModBattleControl), which lets the match runner compare both brains on one build.
    * It is a separate class, like ModGameSpeed, so the battle code does not have to depend
    * on the bridge.
    *
    * It only matters in an offline battle: an online opponent is a person, not this brain.
    */
   public class ModAiBrain
   {

      public static const DREDGE:String = "dredge";

      public static const SEARCH:String = "search";

      /** True for the look-ahead brain. */
      public static var lookahead:Boolean = false;

      public function ModAiBrain()
      {
         super();
      }

      /** The brain's name, as set_ai_brain and the match runner spell it. */
      public static function get brainName() : String
      {
         return lookahead ? SEARCH : DREDGE;
      }
   }
}
