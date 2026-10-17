package engine.mod
{
   /**
    * ModGameSpeed — NEW FILE (not in original decompile).
    *
    * A developer-only fast-forward for unattended test runs (BSF-Client #31).
    * The match runner plays hundreds of turns, and almost all of a turn's time
    * is the game playing its animations, so measuring the computer opponent
    * took about 3½ minutes a battle. This holds one number, how many times
    * faster than normal the game clock runs. GameWrapper multiplies each
    * frame's elapsed time by it, and BattleStateTurnAi divides the opponent's
    * built-in pauses by it.
    *
    * It is 1 (normal speed) unless the mod bridge's "set_game_speed" command
    * changes it, and that command refuses anything above 1 outside an offline
    * practice battle (ModBattleControl). Nothing a player can press reaches it.
    * It is a separate class so the game's main loop does not have to depend on
    * the bridge.
    */
   public class ModGameSpeed
   {

      public static const MAX_SCALE:int = 8;

      private static var s_scale:int = 1;

      public function ModGameSpeed()
      {
         super();
      }

      /** How many times faster than normal the game clock runs; 1 is normal. */
      public static function get scale() : int
      {
         return s_scale;
      }

      /** Clamped to 1..MAX_SCALE, so a bad value can never stop or reverse time. */
      public static function set scale(value:int) : void
      {
         s_scale = int(Math.max(1,Math.min(MAX_SCALE,value)));
      }
   }
}
