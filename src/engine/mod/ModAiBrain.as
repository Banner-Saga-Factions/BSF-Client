package engine.mod
{
   import engine.math.Rng;

   /**
    * ModAiBrain — NEW FILE (not in original decompile).
    *
    * Which brain the offline computer thinks with (BSF-Client #31, Wave 4):
    *
    *   dredge  the planner the game shipped with, plus our fixes (AiModuleDredge)
    *   search  the same planner, plus a one-move look-ahead: before it commits, it asks
    *           what the enemy who acts next could do back to it (AiModuleSearch)
    *
    * Since Wave 4a there is one setting per side: "computer" (the opponent, as before) and
    * "player" (used only while ModAiSides has the computer play the player's side too, so
    * one brain can play the other head to head).
    *
    * It also holds the "near-best" pick for measuring runs (Wave 4a): two fixed brains replay
    * the same battle move for move, so with a margin above 0 each brain chooses at random
    * among its plans that score within that margin of its best. The random numbers come from
    * this class's own generator, made from a seed the match runner sends, never from the
    * game's dice, so battle rolls are untouched. Margin 0, the default, is the normal brain.
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

      /** The two sides, as set_ai_brain and the match runner spell them. */
      public static const COMPUTER:String = "computer";

      public static const PLAYER:String = "player";

      /**
       * True for the look-ahead brain on the computer's side, the default since Wave 4: on one
       * build, 4 battles per brain on each test account, it kept as many or more of its units
       * alive with no new errors (misc/Plan-Improve-Battle-AI.md, Measurements).
       */
      public static var lookahead:Boolean = true;

      /** The same, for the player's side when the computer plays it (ModAiSides). */
      public static var playerLookahead:Boolean = true;

      /**
       * How many points below its best plan a plan may score and still be picked at random.
       * 0 = always the best plan (normal play). Plan scores weigh a point of strength damage
       * at 45 and a kill at 200 (AiPlan), so a small margin only varies near-ties.
       */
      public static var margin:int = 0;

      private static var rng:Rng = null;

      public function ModAiBrain()
      {
         super();
      }

      /** True if the name is one of the two sides. */
      public static function isSide(param1:String) : Boolean
      {
         return param1 === COMPUTER || param1 === PLAYER;
      }

      /** True if that side thinks with the look-ahead brain. */
      public static function lookaheadFor(param1:String) : Boolean
      {
         return param1 === PLAYER ? playerLookahead : lookahead;
      }

      /** Set one side's brain; the name must be DREDGE or SEARCH. */
      public static function setBrain(param1:String, param2:String) : void
      {
         if(param1 === PLAYER)
         {
            playerLookahead = param2 === SEARCH;
         }
         else
         {
            lookahead = param2 === SEARCH;
         }
      }

      /** One side's brain name, as set_ai_brain and the match runner spell it. */
      public static function brainNameFor(param1:String) : String
      {
         return lookaheadFor(param1) ? SEARCH : DREDGE;
      }

      /** The computer's brain name (the setting before Wave 4a). */
      public static function get brainName() : String
      {
         return brainNameFor(COMPUTER);
      }

      /** Start the near-best pick's random numbers from this seed. */
      public static function seed(param1:int) : void
      {
         rng = new Rng(param1);
      }

      /**
       * A number from 0 to count - 1 for the near-best pick. 0 when no seed was ever sent, so
       * a margin without a seed still plays the best plan.
       */
      public static function pickIndex(param1:int) : int
      {
         if(param1 <= 1 || rng == null)
         {
            return 0;
         }
         return rng.nextMax(param1);
      }
   }
}
