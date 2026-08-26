package engine.mod
{
   import engine.ability.def.AbilityDefLevel;
   import engine.battle.ability.def.BattleAbilityDef;
   import engine.battle.ability.def.BattleAbilityDefLevels;
   import engine.battle.ability.def.BattleAbilityTag;
   import engine.battle.ability.def.BattleAbilityTargetRule;
   import engine.battle.ability.model.BattleAbility;
   import engine.battle.ability.model.BattleAbilityValidation;
   import engine.battle.board.model.IBattleEntity;
   import engine.battle.entity.model.BattleEntity;
   import engine.battle.fsm.BattleFsm;
   import engine.battle.fsm.BattleMove;
   import engine.battle.fsm.BattleTurn;
   import engine.battle.fsm.state.BattleStateDeploy;
   import engine.battle.fsm.state.BattleStateTurnLocal;
   import engine.battle.fsm.state.BattleStateTurnLocalBase;
   import engine.core.fsm.Fsm;
   import engine.core.logging.ILogger;
   import engine.stat.def.StatType;
   import engine.tile.Tile;
   import flash.utils.getQualifiedClassName;

   /**
    * ModBattleControl — NEW FILE (not in original decompile).
    *
    * The mod-bridge commands that let an outside program read a battle and play
    * it: "battle_state", "battle_deploy_ready", "battle_end_turn", "battle_move"
    * and "battle_attack". Registered once from GameFsm, alongside
    * "start_ai_battle".
    *
    * WHY IT DUCK-TYPES ONE HOP: the path from the game's state machine down to a
    * battle runs through SceneState, which is game-layer code, while this class
    * is engine-layer. Rather than invert that dependency, the scene hop is done
    * through an untyped reference inside a try/catch — no such property means no
    * battle, which is the same answer we want anyway.
    *
    * NOTHING HERE TALKS TO THE SERVER. Reading touches getters only, and every
    * write goes through a path the game already drives from code rather than
    * from the mouse:
    *
    *   battle_deploy_ready  the same public autoDeployLocal() the Ready button
    *                        calls (BattleHudPage.guiBattleHudDeployReady)
    *   battle_end_turn      the same public skip() the on-screen countdown ring
    *                        calls when a turn runs out
    *   battle_move          what a click on a tile does, then what the second
    *                        click on the same tile does — plan the route, then
    *                        confirm it (BattleBoardController.handleMoveClick)
    *   battle_attack        what the execute button does
    *                        (BattleHudPage.executeTurnAbility)
    *
    * So none of this adds behaviour the game did not already have — it only
    * makes the moment deterministic instead of timed, and reachable without a
    * screen. Two places where the likeness is not exact, both found in review:
    * the move commands skip setWayPoint, so the on-screen waypoint marker stays
    * at the origin; and the attack cannot set BattleHudPage.abilityCommitted,
    * which is game-layer state this engine-layer class cannot reach, so the
    * ability popups are not disabled the way the button disables them. Neither
    * matters to a headless run; both matter if someone clicks mid-script.
    *
    * IN AN OFFLINE BATTLE NOTHING HERE REACHES THE SERVER, and the "offline"
    * is load-bearing. The move and action commands the engine queues send only
    * when the unit is player-controlled AND the battle is online
    * (BattleTurnCmdMove:25, BattleTurnCmdAction:28,36), and the deployment send
    * is gated the same way (BattleStateDeploy:139). An offline practice battle
    * satisfies none of those, so an injected move, attack or ready plays out
    * locally and sends nothing. A LOCAL party's turn in an ONLINE battle runs
    * in this very same BattleStateTurnLocal (BattleStateNextTurn:54-55), so
    * used there these commands send exactly what the mouse would.
    *
    * NOTHING HERE THROWS AT THE HOST. Every handler is wrapped; a fault comes
    * back as a described refusal rather than as an ERROR line. Note the shapes
    * differ: the four commands that do something answer {"ok":…}, while
    * battle_state answers a description with no "ok" field at all.
    */
   public class ModBattleControl
   {

      /**
       * How far from the origin a tile coordinate may sensibly be. Looking a
       * tile up goes through TileLocation.fetch, which remembers every pair of
       * coordinates it is ever asked about, so a wild number from a host would
       * leave an entry behind for nothing. No board comes near this, so
       * anything past it is a typo, not a tile.
       */
      private static const TILE_LIMIT:int = 1000;

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
         // Every handler is wrapped, so the "nothing throws at the host" promise
         // in this file's header holds for all five and not just for the ones
         // that happen to have their own catch.
         ModBridge.registerCommand("battle_state",function(cmd:Object):Object
         {
            try
            {
               return describeBattle();
            }
            catch(e:Error)
            {
               return {
                  "inBattle":false,
                  "error":"could not read the battle: " + e.message
               };
            }
         });
         ModBridge.registerCommand("battle_end_turn",function(cmd:Object):Object
         {
            try
            {
               return endCurrentTurn();
            }
            catch(e2:Error)
            {
               return {
                  "ok":false,
                  "reason":"the game refused to end the turn",
                  "error":e2.message
               };
            }
         });
         ModBridge.registerCommand("battle_deploy_ready",function(cmd:Object):Object
         {
            return readyDeployment();
         });
         ModBridge.registerCommand("battle_move",function(cmd:Object):Object
         {
            return issueMove(cmd);
         });
         ModBridge.registerCommand("battle_attack",function(cmd:Object):Object
         {
            return issueAttack(cmd);
         });
         if(logger)
         {
            logger.info("ModBridge commands registered: battle_state, battle_deploy_ready, battle_end_turn, battle_move, battle_attack");
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
               "complete":turn.complete,
               // The two a host needs to make sense of a refusal: has this unit
               // already walked, and is it already carrying an ability?
               "moved":turn.move != null && turn.move.committed,
               "ability":turn.ability == null ? null : turn.ability.def.id
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
       * End the turn that is running now, whoever it belongs to — the player's
       * own or the computer's, which is worth having when one gets stuck. What
       * it cannot end is a turn this copy of the game is not running: the other
       * player's turn in an online battle, or a moment between turns such as
       * deploying. Says why rather than failing silently.
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
               "reason":"this turn cannot be ended from outside",
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
         // A turn that is already committed is already ending. Calling skip()
         // anyway does no harm, but the engine logs "Attempting to re-terminate"
         // as an error — a scary line for something the host did not do wrong.
         if(fsm.turn != null && fsm.turn.committed)
         {
            return {
               "ok":false,
               "reason":"this turn is already committed"
            };
         }
         // Read the number BEFORE ending it. skip() runs the whole termination
         // through synchronously, so by the time it returns fsm.turn is the
         // NEXT turn — reporting that would quietly hand a host the wrong number
         // and disagree with what battle_move and battle_attack report.
         var ended:int = fsm.turn == null ? -1 : fsm.turn.number;
         local.skip();
         if(s_logger)
         {
            s_logger.info("ModBattleControl ended turn " + ended + " on request");
         }
         return {
            "ok":true,
            "turn":ended,
            "next":fsm.turn == null ? -1 : fsm.turn.number,
            "state":shortStateName(fsm)
         };
      }

      /**
       * Say "ready" on the deploy screen, which is what starts the fighting.
       *
       * WHY THIS COMMAND HAS TO EXIST — MEASURED, NOT INFERRED. An offline
       * practice battle never leaves the deploy phase on its own. The engine
       * zeroes the deploy countdown for any battle that is not online
       * (BattleFsm:114), and a countdown of zero means no timer is ever created
       * (BaseBattleState:84), so the phase's own force-deploy can never fire.
       * The only other way out is the Ready button on screen, which calls the
       * public autoDeployLocal() this command calls. Without it a scripted
       * battle sits in deploy for ever and never reaches a turn — which is
       * exactly what a run on 2026-08-26 showed, three readings apart.
       *
       * Units are already standing on their tiles by then: entering the phase
       * places them (BattleStateDeploy.handleEnteredState). What is missing is
       * only the confirmation, so this changes where nothing and starts the
       * battle as laid out.
       *
       * The reported "state" is the one the battle moved to, since readying
       * finishes the phase then and there.
       */
      private static function readyDeployment() : Object
      {
         var fsm:BattleFsm = currentBattle();
         if(fsm == null)
         {
            return {
               "ok":false,
               "reason":"not in a battle"
            };
         }
         var deploy:BattleStateDeploy = fsm.current as BattleStateDeploy;
         if(deploy == null)
         {
            return {
               "ok":false,
               "reason":"not in the deploy phase",
               "state":shortStateName(fsm)
            };
         }
         if(deploy.isLocalDeployed)
         {
            return {
               "ok":false,
               "reason":"this side has already said ready"
            };
         }
         try
         {
            deploy.autoDeployLocal();
         }
         catch(e:Error)
         {
            return {
               "ok":false,
               "reason":"the game refused to start the battle",
               "error":e.message
            };
         }
         if(s_logger)
         {
            s_logger.info("ModBattleControl said ready on the deploy screen on request");
         }
         return {
            "ok":true,
            "state":shortStateName(fsm)
         };
      }

      // ---------------------------------------------------------------------
      // Playing a turn: move, then attack
      // ---------------------------------------------------------------------

      /**
       * Everything that must be true before either command touches anything,
       * in one place. Returns the refusal to send back, or null when all is well.
       *
       * WHY THE EXACT SUBCLASS, and not the base class battle_end_turn accepts:
       * BattleStateTurnLocal is the only state that listens for a move or a turn
       * being committed and turns that into a queued command. Committing on any
       * other state would raise the flag with nothing watching for it, and the
       * turn would simply stall.
       */
      private static function refuseUnlessPlayerCanAct(fsm:BattleFsm) : Object
      {
         if(fsm == null)
         {
            return {
               "ok":false,
               "reason":"not in a battle"
            };
         }
         var state:BattleStateTurnLocal = fsm.current as BattleStateTurnLocal;
         if(state == null)
         {
            return {
               "ok":false,
               "reason":"not a player-controlled turn",
               "state":shortStateName(fsm)
            };
         }
         if(state.skipped)
         {
            return {
               "ok":false,
               "reason":"this turn was already ended"
            };
         }
         if(fsm.turn == null)
         {
            return {
               "ok":false,
               "reason":"no turn is running"
            };
         }
         if(fsm.turn.committed)
         {
            return {
               "ok":false,
               "reason":"this turn is already committed"
            };
         }
         return null;
      }

      /**
       * Walk the unit whose turn it is to a tile: {"cmd":"battle_move","x":4,"y":2}.
       * The coordinates are the ones battle_state already reports for every unit.
       *
       * The host names a destination, not a route — the engine's own pathfinder
       * works out the steps, exactly as it does for a click. A tile the player
       * could not have clicked is refused: isInRange() asks the same reach map
       * the highlighted tiles on screen are drawn from.
       *
       * Moving does not end the turn, so the pair to follow this with is either
       * battle_attack or battle_end_turn.
       */
      private static function issueMove(cmd:Object) : Object
      {
         try
         {
            return attemptMove(cmd);
         }
         catch(e:Error)
         {
            var fsm:BattleFsm = currentBattle();
            var move:BattleMove = fsm == null || fsm.turn == null ? null : fsm.turn.move;
            var started:Boolean = move != null && move.committed;
            undoUncommittedMove(move);
            return {
               "ok":false,
               "reason":"the game refused the move",
               "error":e.message,
               // True means the move had already been accepted and the fault came
               // afterwards, while the unit was walking — so the board may have
               // changed even though this says no.
               "committed":started
            };
         }
      }

      /** The work of battle_move. Its wrapper above is what keeps a fault in
       *  here from reaching the host as a bare error line. */
      private static function attemptMove(cmd:Object) : Object
      {
         var fsm:BattleFsm = currentBattle();
         var refusal:Object = refuseUnlessPlayerCanAct(fsm);
         if(refusal != null)
         {
            return refusal;
         }
         var turn:BattleTurn = fsm.turn;
         var move:BattleMove = turn.move;
         if(move == null)
         {
            return {
               "ok":false,
               "reason":"this turn has no move to make"
            };
         }
         if(move.committed)
         {
            return {
               "ok":false,
               "reason":"this unit has already moved"
            };
         }
         if(!isTileNumber(cmd,"x") || !isTileNumber(cmd,"y"))
         {
            return {
               "ok":false,
               "reason":"a move needs a whole-number x and y"
            };
         }
         var x:int = int(cmd.x);
         var y:int = int(cmd.y);
         var where:String = x + "," + y;
         var tile:Tile = fsm.board.tiles.getTile(x,y);
         if(tile == null)
         {
            return {
               "ok":false,
               "reason":"no tile at " + where
            };
         }
         if(tile == move.last)
         {
            return {
               "ok":false,
               "reason":"already standing there"
            };
         }
         if(!move.isInRange(tile))
         {
            return {
               "ok":false,
               "reason":where + " is out of reach this turn"
            };
         }
         var entityId:String = turn.entity == null ? null : turn.entity.id;
         var from:Object = tileXY(move.first);
         // What two clicks do: work out the route, then confirm it. (The click
         // path also sets a waypoint between the two; skipping it only affects
         // the marker drawn on screen, since this confirms straight away.)
         move.process(tile,true);
         // process() can decline without saying so — a tile inside the reach map
         // with no route through it leaves the move where it started.
         if(move.last != tile)
         {
            undoUncommittedMove(move);
            return {
               "ok":false,
               "reason":"no path to " + where
            };
         }
         // Committing is what sets the unit walking: the turn state is listening
         // for it and queues the movement command the moment it happens.
         move.setCommitted("ModBattleControl.battle_move");
         if(s_logger)
         {
            s_logger.info("ModBattleControl moved " + entityId + " to " + where + " on request");
         }
         return {
            "ok":true,
            "entityId":entityId,
            "from":from,
            "to":tileXY(tile),
            "steps":move.numSteps - 1,
            "turn":turn.number
         };
      }

      /**
       * Swing at another unit: {"cmd":"battle_attack","target":"<unit id>"}.
       *
       * "ability" is optional and takes either of two plain words — "strength"
       * or "armor" — so a test need not know that a Raider swings abl_melee_str
       * while an Archer looses abl_bow_str. Any other value is read as a literal
       * ability id, and "level" picks which level of it. Left out entirely it
       * means the strength attack, falling back to the armor one for a unit that
       * has no strength attack at all.
       *
       * THIS ENDS THE TURN, because that is what it does on screen: the execute
       * button commits the turn and the engine treats the ability as the turn's
       * last act. If a move is still pending it is committed first, so the unit
       * walks and then swings, in that order — the engine sequences the two
       * itself, so a host may send this while the unit is still walking.
       */
      private static function issueAttack(cmd:Object) : Object
      {
         try
         {
            return attemptAttack(cmd);
         }
         catch(e:Error)
         {
            var fsm:BattleFsm = currentBattle();
            var turn:BattleTurn = fsm == null ? null : fsm.turn;
            // An attack changes three things in a row, and a fault can land
            // between any two of them. "committed" has to mean "some of it had
            // already taken effect", so it asks about the move as well as the
            // turn — committing the move is what starts the unit walking.
            var took:Boolean = turn != null && (turn.committed || turn.move != null && turn.move.committed);
            if(!took)
            {
               undoUnstartedAbility(turn);
            }
            return {
               "ok":false,
               "reason":"the game refused the attack",
               "error":e.message,
               "committed":took
            };
         }
      }

      /** The work of battle_attack. Its wrapper above is what keeps a fault in
       *  here from reaching the host as a bare error line. */
      private static function attemptAttack(cmd:Object) : Object
      {
         var fsm:BattleFsm = currentBattle();
         var refusal:Object = refuseUnlessPlayerCanAct(fsm);
         if(refusal != null)
         {
            return refusal;
         }
         var turn:BattleTurn = fsm.turn;
         if(turn.ability != null && (turn.ability.executing || turn.ability.executed))
         {
            return {
               "ok":false,
               "reason":"this unit has already acted"
            };
         }
         var caster:IBattleEntity = turn.entity;
         if(caster == null)
         {
            return {
               "ok":false,
               "reason":"no unit is taking this turn"
            };
         }
         var level:int = 1;
         if(cmd != null && cmd.hasOwnProperty("level"))
         {
            if(!isWholeNumber(cmd,"level"))
            {
               return {
                  "ok":false,
                  "reason":"level must be a whole number"
               };
            }
            level = int(cmd.level);
         }
         var wanted:String = cmd != null && cmd.ability != null ? String(cmd.ability) : null;
         var lookup:Object = attackDefFor(fsm,caster,wanted,level);
         if(lookup.hasOwnProperty("reason"))
         {
            return {
               "ok":false,
               "reason":lookup.reason
            };
         }
         var def:BattleAbilityDef = lookup.def as BattleAbilityDef;
         if(def == null)
         {
            return {
               "ok":false,
               "reason":"that ability is not one a unit can be told to use here"
            };
         }
         if(def.targetRule == BattleAbilityTargetRule.TILE_ANY || def.targetRule == BattleAbilityTargetRule.TILE_EMPTY)
         {
            return {
               "ok":false,
               "reason":"this ability aims at a tile, which the bridge cannot do yet",
               "ability":def.id
            };
         }
         // An ability that hits several units at once is aimed differently on
         // screen: the click path sweeps up neighbours until it has as many as
         // the ability takes (BattleBoardController.handleAbilityAdjacentClick).
         // Naming one target here would quietly hit one instead of all of them,
         // so refuse rather than half-do it.
         if(def.targetCount > 1)
         {
            return {
               "ok":false,
               "reason":"this ability hits several units at once, which the bridge cannot aim yet",
               "ability":def.id,
               "targetCount":def.targetCount
            };
         }
         var target:IBattleEntity = null;
         if(cmd != null && cmd.target != null)
         {
            target = fsm.board.getEntity(String(cmd.target));
            if(target == null)
            {
               return {
                  "ok":false,
                  "reason":"no unit with id " + cmd.target
               };
            }
         }
         else if(def.targetCount > 0)
         {
            return {
               "ok":false,
               "reason":"an attack needs a target"
            };
         }
         // The engine's own verdict on whether this swing is legal — the same
         // check that decides whether the game lets you click the target.
         var verdict:BattleAbilityValidation = BattleAbilityValidation.validate(def,caster,turn.move,target,null,false,true);
         if(verdict != BattleAbilityValidation.OK)
         {
            return {
               "ok":false,
               "reason":"the game rejected that attack",
               "validation":verdict == null ? null : verdict.name,
               "ability":def.id
            };
         }
         var ability:BattleAbility = new BattleAbility(caster,def,fsm.board.abilityManager);
         if(target != null)
         {
            ability.targetSet.setTarget(target);
         }
         if(!ability.checkCosts(true))
         {
            return {
               "ok":false,
               "reason":"this unit cannot pay for that ability",
               "ability":def.id
            };
         }
         // This exact order is BattleHudPage.executeTurnAbility's: hand the turn
         // its ability, commit any pending move so the unit walks first, then
         // commit the turn — which is what sets the ability going.
         turn.ability = ability;
         if(turn.move != null && !turn.move.committed)
         {
            turn.move.setCommitted("ModBattleControl.battle_attack");
         }
         turn.committed = true;
         if(s_logger)
         {
            s_logger.info("ModBattleControl had " + caster.id + " use " + def.id + " on request");
         }
         return {
            "ok":true,
            "entityId":caster.id,
            "ability":def.id,
            "level":def.level,
            "target":target == null ? null : target.id,
            "turn":turn.number
         };
      }

      /**
       * Work out which ability to swing, and answer either {"def":…} or
       * {"reason":…}. Two of the calls in here throw rather than answering null,
       * so neither is made blind: the ability table's fetch() throws on an
       * unknown id unless told otherwise, and asking an ability for a level it
       * does not have throws as well.
       */
      private static function attackDefFor(fsm:BattleFsm, caster:IBattleEntity, wanted:String, level:int) : Object
      {
         var root:BattleAbilityDef = null;
         var chosen:AbilityDefLevel = null;
         if(wanted != null && wanted != "strength" && wanted != "armor")
         {
            root = fsm.board.abilityManager.factory.fetch(wanted,false) as BattleAbilityDef;
            if(root == null)
            {
               return {"reason":"unknown ability: " + wanted};
            }
         }
         else
         {
            // The unit's own basic attacks, looked up the way the computer
            // opponent looks them up (AiModuleBase). A unit may have only one
            // of the two — a Shieldbanger has no strength attack at all.
            var attacks:BattleAbilityDefLevels = caster.def.attacks as BattleAbilityDefLevels;
            if(attacks == null)
            {
               return {"reason":"this unit has no attacks"};
            }
            if(wanted != "armor")
            {
               chosen = attacks.getFirstAbilityByTag(BattleAbilityTag.ATTACK_STR);
            }
            if(chosen == null && wanted != "strength")
            {
               chosen = attacks.getFirstAbilityByTag(BattleAbilityTag.ATTACK_ARM);
            }
            if(chosen == null)
            {
               return {"reason":"this unit has no " + (wanted == null ? "basic" : wanted) + " attack"};
            }
            root = chosen.def as BattleAbilityDef;
            if(root == null)
            {
               return {"reason":"this unit's " + (wanted == null ? "basic" : wanted) + " attack is not a battle ability"};
            }
         }
         if(level < 1 || level > root.maxLevel)
         {
            return {"reason":"ability " + root.id + " has no level " + level};
         }
         return {"def":root.getBattleAbilityDefLevel(level)};
      }

      /**
       * Take back an ability that was handed to the turn but never got going,
       * so a refused attack leaves the turn as it found it. Only safe while the
       * ability has not started — the setter itself refuses once it has, which
       * is the case the caller has already ruled out by checking that nothing
       * committed. Swallows its own failure for the same reason as below.
       */
      private static function undoUnstartedAbility(turn:BattleTurn) : void
      {
         try
         {
            if(turn != null && turn.ability != null && !turn.ability.executing && !turn.ability.executed)
            {
               turn.ability = null;
            }
         }
         catch(e:Error)
         {
            if(s_logger)
            {
               s_logger.info("ModBattleControl could not take back an unstarted ability: " + e.message);
            }
         }
      }

      /**
       * Put a half-built move back where it started, so a refused request leaves
       * the turn exactly as it found it. Swallows its own failure on purpose:
       * this only ever runs while answering some earlier problem, and a second
       * error here would replace the first one's explanation with a worse one.
       */
      private static function undoUncommittedMove(move:BattleMove) : void
      {
         try
         {
            if(move != null && !move.committed && move.numSteps > 1)
            {
               move.reset(move.first);
            }
         }
         catch(e:Error)
         {
            if(s_logger)
            {
               s_logger.info("ModBattleControl could not undo a half-built move: " + e.message);
            }
         }
      }

      /** {"x":4,"y":2} for a tile, or null when there isn't one. */
      private static function tileXY(tile:Tile) : Object
      {
         if(tile == null || tile.location == null)
         {
            return null;
         }
         return {
            "x":tile.location.x,
            "y":tile.location.y
         };
      }

      /** Is this field present and a whole number? Insists on an actual number
       *  rather than letting Number() turn null, "" or false into a quiet zero —
       *  {"x":null} should be refused, not read as tile 0. */
      private static function isWholeNumber(cmd:Object, field:String) : Boolean
      {
         if(cmd == null || !cmd.hasOwnProperty(field))
         {
            return false;
         }
         var raw:Object = cmd[field];
         if(!(raw is Number) && !(raw is int) && !(raw is uint))
         {
            return false;
         }
         var value:Number = Number(raw);
         return !isNaN(value) && isFinite(value) && value == Math.floor(value);
      }

      /** As above, and near enough the origin to be a real board coordinate. */
      private static function isTileNumber(cmd:Object, field:String) : Boolean
      {
         return isWholeNumber(cmd,field) && Math.abs(Number(cmd[field])) <= TILE_LIMIT;
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
