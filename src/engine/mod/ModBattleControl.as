package engine.mod
{
   import engine.battle.entity.model.BattleEntity;
   import engine.battle.fsm.BattleFsm;
   import engine.battle.fsm.BattleTurn;
   import engine.battle.fsm.state.BattleStateTurnLocalBase;
   import engine.core.fsm.Fsm;
   import engine.core.logging.ILogger;
   import engine.stat.def.StatType;
   import flash.utils.getQualifiedClassName;

   /**
    * ModBattleControl — NEW FILE (not in original decompile).
    *
    * The mod-bridge commands that let an outside program read a battle and
    * advance it: "battle_state" and "battle_end_turn". Registered once from
    * GameFsm, alongside "start_ai_battle".
    *
    * WHY IT DUCK-TYPES ONE HOP: the path from the game's state machine down to a
    * battle runs through SceneState, which is game-layer code, while this class
    * is engine-layer. Rather than invert that dependency, the scene hop is done
    * through an untyped reference inside a try/catch — no such property means no
    * battle, which is the same answer we want anyway.
    *
    * NOTHING HERE TALKS TO THE SERVER. Reading touches getters only. The single
    * write, "battle_end_turn", calls the same public skip() the on-screen turn
    * countdown already calls when a turn runs out, so it adds no behaviour the
    * game did not already have — it only makes the moment deterministic instead
    * of timed.
    */
   public class ModBattleControl
   {

      private static var s_gameFsm:Fsm;

      private static var s_logger:ILogger;

      public function ModBattleControl()
      {
         super();
      }

      /**
       * Called once, from GameFsm, when the top-level game state is built. The
       * bridge's registry is static and keeps registrations made before a host
       * connects, so this is safe with or without a host present.
       */
      public static function register(gameFsm:Fsm, logger:ILogger) : void
      {
         s_gameFsm = gameFsm;
         s_logger = logger;
         ModBridge.registerCommand("battle_state",function(cmd:Object):Object
         {
            return describeBattle();
         });
         ModBridge.registerCommand("battle_end_turn",function(cmd:Object):Object
         {
            return endCurrentTurn();
         });
         if(logger)
         {
            logger.info("ModBridge commands registered: battle_state, battle_end_turn");
         }
      }

      /**
       * Stats worth reporting, named as the stat panel names them on screen
       * rather than as the internal enum spells them. Built on each call rather
       * than held in a static, so this never depends on which class finished
       * initialising first.
       */
      private static function reportedStats() : Array
      {
         return [{
            "name":"strength",
            "type":StatType.STRENGTH
         },{
            "name":"armor",
            "type":StatType.ARMOR
         },{
            "name":"willpower",
            "type":StatType.WILLPOWER
         },{
            "name":"exertion",
            "type":StatType.EXERTION
         },{
            "name":"break",
            "type":StatType.ARMOR_BREAK
         },{
            "name":"movement",
            "type":StatType.MOVEMENT
         },{
            "name":"range",
            "type":StatType.RANGE
         }];
      }

      /** The live battle, or null when the game is not in one. */
      private static function currentBattle() : BattleFsm
      {
         if(s_gameFsm == null)
         {
            return null;
         }
         var state:Object = s_gameFsm.current;
         if(state == null)
         {
            return null;
         }
         var scene:Object = null;
         try
         {
            // SceneState.scene — every other game state simply lacks it.
            scene = state["scene"];
         }
         catch(e:Error)
         {
            return null;
         }
         if(scene == null)
         {
            return null;
         }
         var board:Object = scene.focusedBoard;
         // board.fsm reads through sim, so an un-simulated board would throw.
         if(board == null || board.sim == null)
         {
            return null;
         }
         return board.fsm as BattleFsm;
      }

      /**
       * Everything an outside checker needs to assert on, and no more: which
       * battle, whose turn it is, and every unit's side, place and numbers.
       */
      private static function describeBattle() : Object
      {
         var fsm:BattleFsm = currentBattle();
         if(fsm == null)
         {
            return {"inBattle":false};
         }
         var out:Object = {
            "inBattle":true,
            "battleId":fsm.battleId,
            "online":fsm.isOnline,
            "finished":fsm.battleFinished,
            "state":shortStateName(fsm)
         };
         var turn:BattleTurn = fsm.turn;
         if(turn == null)
         {
            out.turn = null;
         }
         else
         {
            out.turn = {
               "number":turn.number,
               "entityId":turn.entity == null ? null : turn.entity.id,
               "playerControlled":turn.entity != null && turn.entity.playerControlled,
               "committed":turn.committed,
               "complete":turn.complete
            };
         }
         var units:Array = [];
         for each(var entity:Object in fsm.board.entities)
         {
            // Skip scenery props exactly as the offline AI does: they are alive
            // board entities with a team but no combat stats, so reading a stat
            // off one throws "No such stat: ARMOR". Every real combatant has it.
            // Unlike the AI we deliberately keep DEAD units — a checker watching
            // for a crash wants to see the casualty, not have it vanish.
            if(entity == null || entity.stats == null || !entity.stats.hasStat(StatType.ARMOR))
            {
               continue;
            }
            units.push(describeUnit(entity as BattleEntity));
         }
         out.units = units;
         return out;
      }

      private static function describeUnit(entity:BattleEntity) : Object
      {
         var unit:Object = {
            "id":entity.id,
            "name":entity.name,
            "team":entity.team,
            "playerControlled":entity.playerControlled,
            "alive":entity.alive,
            "tile":null,
            "stats":{}
         };
         if(entity.tile != null && entity.tile.location != null)
         {
            unit.tile = {
               "x":entity.tile.location.x,
               "y":entity.tile.location.y
            };
         }
         for each(var stat:Object in reportedStats())
         {
            if(entity.stats.hasStat(stat.type))
            {
               // current / base — the same two numbers the stat panel shows, the
               // second being what the unit was built with before buffs and harm.
               unit.stats[stat.name] = {
                  "current":entity.stats.getValue(stat.type),
                  "base":entity.stats.getStat(stat.type).original
               };
            }
         }
         return unit;
      }

      /**
       * End the turn that is running now. Only a local turn can be ended this
       * way — the computer's turns end themselves, and there is nothing sensible
       * to do to one from outside. Says why rather than failing silently.
       */
      private static function endCurrentTurn() : Object
      {
         var fsm:BattleFsm = currentBattle();
         if(fsm == null)
         {
            return {
               "ok":false,
               "reason":"not in a battle"
            };
         }
         var local:BattleStateTurnLocalBase = fsm.current as BattleStateTurnLocalBase;
         if(local == null)
         {
            return {
               "ok":false,
               "reason":"not a local turn",
               "state":shortStateName(fsm)
            };
         }
         if(local.skipped)
         {
            return {
               "ok":false,
               "reason":"this turn was already ended"
            };
         }
         local.skip();
         if(s_logger)
         {
            s_logger.info("ModBattleControl ended the current turn on request");
         }
         return {
            "ok":true,
            "turn":fsm.turn == null ? -1 : fsm.turn.number
         };
      }

      /** "BattleStateTurnAi" rather than the full package path — matches the
       *  names that appear in the game log. */
      private static function shortStateName(fsm:BattleFsm) : String
      {
         if(fsm.currentClass == null)
         {
            return null;
         }
         var full:String = getQualifiedClassName(fsm.currentClass);
         return full.substr(full.lastIndexOf(":") + 1);
      }
   }
}
