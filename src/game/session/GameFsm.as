package game.session
{
   import engine.core.fsm.Fsm;
   import engine.core.fsm.StateData;
   import engine.mod.ModBridge;
   import engine.core.http.HttpAction;
   import engine.core.http.HttpCommunicator;
   import engine.core.http.HttpJsonAction;
   import engine.core.util.Enum;
   import engine.session.Chat;
   import engine.session.ChatMsg;
   import engine.session.ChatRoomMsg;
   import engine.session.Credentials;
   import engine.session.ServerStatusData;
   import engine.session.Session;
   import engine.session.TxnGet;
   import game.cfg.GameConfig;
   import game.gui.IGuiDialog;
   import game.session.actions.GameLocationTxn;
   import game.session.actions.LogoutTxn;
   import game.session.actions.VsType;
   import game.session.states.AccountInfoState;
   import game.session.states.AssembleHeroesState;
   import game.session.states.AuthBuildMismatchState;
   import game.session.states.AuthFailedState;
   import game.session.states.AuthState;
   import game.session.states.FactionsState;
   import game.session.states.FlashState;
   import game.session.states.FriendLobbyState;
   import game.session.states.GreatHallState;
   import game.session.states.HallOfValorState;
   import game.session.states.LoginQueueState;
   import game.session.states.MainMenuState;
   import game.session.states.MapCampLoadState;
   import game.session.states.MapCampState;
   import game.session.states.MeadHouseState;
   import game.session.states.OfflineState;
   import game.session.states.PreAuthState;
   import game.session.states.ProvingGroundsState;
   import game.session.states.ReadyState;
   import game.session.states.AiBattleLoadState;
   import game.session.states.GameStateDataEnum;
   import game.session.states.SagaState;
   import game.session.states.SceneLoadState;
   import game.session.states.SceneState;
   import game.session.states.SkirmishState;
   import game.session.states.StartState;
   import game.session.states.TownLoadState;
   import game.session.states.TownState;
   import game.session.states.VersusCancelState;
   import game.session.states.VersusFailState;
   import game.session.states.VersusFindMatchState;
   import game.session.states.VersusMatchedState;
   import game.session.states.VideoQueueState;
   import game.session.states.VideoState;
   import game.session.states.VideoTutorial1State;
   import game.session.states.VideoTutorial2State;
   import game.session.states.tutorial.RegisterTutorialStates;
   import tbs.srv.battle.data.BattleNotification;
   import tbs.srv.data.FriendData;
   import tbs.srv.data.FriendOnlineData;
   import tbs.srv.data.GameLocationData;
   import tbs.srv.data.PurchasableUnitsData;
   import tbs.srv.data.VsQueueData;
   import tbs.srv.util.AchievementProgressData;
   import tbs.srv.util.CurrencyData;
   import tbs.srv.util.RenownMsg;
   import tbs.srv.util.SystemMsg;
   import tbs.srv.util.UnitAddData;
   import tbs.srv.util.UnlockData;
   
   public class GameFsm extends Fsm
   {
      
      public var config:GameConfig;
      
      public var _communicator:HttpCommunicator;
      
      public var credentials:Credentials;
      
      public var session:Session;
      
      public var chat:Chat;
      
      public var playersOnline:int;
      
      private var lastRenownMsgTimestamp:int;
      
      private var disconnectingDialog:IGuiDialog;
      
      public function GameFsm(param1:GameConfig)
      {
         super("GameFsm",param1.logger);
         this.config = param1;
         this.credentials = new Credentials(param1.username,param1.options.accountChildNumber,param1.gameServerUrl,11,param1.logger);
         useMsgQueue();
         registerState(StartState);
         registerState(PreAuthState);
         registerState(FactionsState);
         registerState(SagaState);
         registerState(AuthState);
         registerState(AuthBuildMismatchState);
         registerState(AuthFailedState);
         registerState(AccountInfoState);
         registerState(OfflineState);
         registerState(ReadyState);
         registerState(MainMenuState);
         registerState(TownState);
         registerState(TownLoadState);
         registerState(MapCampState);
         registerState(MapCampLoadState);
         registerState(SceneState);
         registerState(SceneLoadState);
         registerState(AiBattleLoadState);
         registerState(GreatHallState);
         registerState(MeadHouseState);
         registerState(HallOfValorState);
         registerState(LoginQueueState);
         registerState(SkirmishState);
         registerState(VersusFindMatchState);
         registerState(VersusCancelState);
         registerState(VersusMatchedState);
         registerState(ProvingGroundsState);
         registerState(AssembleHeroesState);
         registerState(VersusFailState);
         registerState(FriendLobbyState);
         registerState(VideoQueueState);
         registerState(FlashState);
         registerState(VideoState);
         registerState(VideoTutorial1State);
         registerState(VideoTutorial2State);
         registerTransition(OfflineState,ReadyState,1);
         registerTransition(StartState,PreAuthState,1);
         registerTransition(PreAuthState,AuthState,1);
         registerTransition(AuthBuildMismatchState,AccountInfoState,1);
         registerTransition(AuthBuildMismatchState,AuthFailedState,2);
         registerTransition(AuthState,AccountInfoState,1);
         registerTransition(AuthState,AuthFailedState,2);
         registerTransition(AuthFailedState,PreAuthState,1);
         registerTransition(AccountInfoState,ReadyState,1);
         registerTransition(ReadyState,MainMenuState,1);
         registerTransition(FactionsState,TownLoadState,1);
         registerTransition(VideoQueueState,VideoState,1);
         registerTransition(SceneLoadState,SceneState,1);
         registerTransition(TownLoadState,TownState,1);
         registerTransition(MapCampLoadState,MapCampState,1);
         registerTransition(SceneLoadState,TownLoadState,2);
         // Offline vs-AI: same exits as SceneLoadState -- load completes -> SceneState (the battle);
         // priority-2 fallback -> TownLoadState. The post-battle return to the menu is handled by
         // SceneState.sceneExitHandler (-> TownLoadState in town runMode), exactly like Skirmish.
         registerTransition(AiBattleLoadState,SceneState,1);
         registerTransition(AiBattleLoadState,TownLoadState,2);
         registerTransition(VersusFindMatchState,VersusMatchedState,1);
         registerTransition(VersusFindMatchState,VersusFailState,2);
         registerTransition(VersusMatchedState,SceneLoadState,1);
         registerTransition(VersusMatchedState,VersusFindMatchState,2);
         registerTransition(VideoTutorial1State,TownState,1);
         registerTransition(VideoTutorial2State,TownState,1);
         RegisterTutorialStates.register(this);
         initialState = StartState;
         _communicator = new HttpCommunicator(logger,credentials.gameServerUrl,txnProcessedCallback,txnPollCallback);
         session = new Session(_communicator,credentials);
         this.chat = new Chat(session,param1.friends,param1.logger);

         // Host-ready seam: expose the offline vs-AI battle to ModBridge so mods/host.exe (or any
         // bridge client) can launch it with NO further client build. Reuses set_spectator /
         // ModBridge.spectatorMode for the spectate flag. ModBridge's registry is static and keeps
         // this even if the host isn't running yet. (AS3 closures don't bind `this`, so capture it.)
         var self:GameFsm = this;
         ModBridge.registerCommand("start_ai_battle",function(param1:Object):Object
         {
            var _loc2_:Boolean = (param1 != null && param1.spectate == true) || ModBridge.spectatorMode;
            var _loc3_:String = param1 != null ? param1.scene as String : null;
            self.startAiBattle(_loc2_,_loc3_);
            return "ok";
         });
         logger.info("ModBridge command registered: start_ai_battle");
      }

      /**
       * Launch an OFFLINE practice/spectate battle vs the dormant single-player AI. Single entry point
       * shared by the ModBridge "start_ai_battle" command and the debug keybind. Builds a fresh
       * StateData (spectate flag + optional scene-URL override) and jumps to AiBattleLoadState, which
       * sets up the mirrored parties and runs the battle with no /battle/* traffic. The session
       * long poll keeps running throughout; see AiBattleLoadState's header for what still is sent.
       */
      public function startAiBattle(param1:Boolean, param2:String = null) : void
      {
         var _loc3_:StateData = new StateData();
         _loc3_.setValue(GameStateDataEnum.SPECTATE,param1);
         if(param2)
         {
            _loc3_.setValue(GameStateDataEnum.SCENE_URL,param2);
         }
         logger.info("GameFsm.startAiBattle spectate=" + param1 + " scene=" + (param2 ? param2 : "<default>"));
         transitionTo(AiBattleLoadState,_loc3_);
      }

      public function get communicator() : HttpCommunicator
      {
         return session.communicator;
      }
      
      override protected function cleanup() : void
      {
         config.steamworks.SteamAPI_Shutdown();
         logout();
      }
      
      public function logout() : void
      {
         var _loc1_:LogoutTxn = null;
         if(session.credentials.sessionKey)
         {
            _loc1_ = new LogoutTxn(session.credentials,null,logger);
            session.credentials.sessionKey = null;
            _loc1_.send(session.communicator);
            if(session.communicator)
            {
               session.communicator.connected = false;
            }
            session.credentials.offline = true;
         }
      }
      
      public function get currentGameState() : GameState
      {
         return current as GameState;
      }
      
      override public function handleOneMessage(param1:Object) : Boolean
      {
         var _loc13_:VsQueueData = null;
         var _loc9_:VsType = null;
         var _loc14_:AchievementProgressData = null;
         var _loc6_:GameLocationData = null;
         var _loc11_:FriendOnlineData = null;
         var _loc16_:FriendData = null;
         var _loc17_:ChatMsg = null;
         var _loc8_:FriendData = null;
         var _loc2_:PurchasableUnitsData = null;
         var _loc3_:ServerStatusData = null;
         var _loc12_:ChatMsg = null;
         var _loc18_:ChatRoomMsg = null;
         var _loc4_:SystemMsg = null;
         var _loc10_:BattleNotification = null;
         var _loc5_:RenownMsg = null;
         var _loc19_:UnlockData = null;
         var _loc15_:UnitAddData = null;
         var _loc7_:CurrencyData = null;
         if(!current)
         {
            return false;
         }
         if(config.factions)
         {
            if(config.factions.handleOneMessage(param1))
            {
               return true;
            }
         }
         if(param1["class"] == "tbs.srv.data.VsQueueData")
         {
            if(config.factions)
            {
               _loc13_ = new VsQueueData().parseJson(param1,logger);
               _loc9_ = Enum.parse(VsType,_loc13_.type,false) as VsType;
               config.factions.vsmonitor.updateEntry(_loc9_,_loc13_.powers,_loc13_.counts);
            }
            return true;
         }
         if(param1["class"] == "tbs.srv.util.AchievementProgressData")
         {
            _loc14_ = new AchievementProgressData();
            _loc14_.parseJson(param1,logger);
            logger.debug("handleOneMessage: " + _loc14_);
            return true;
         }
         if(param1["class"] == "tbs.srv.data.GameLocationData")
         {
            _loc6_ = new GameLocationData();
            _loc6_.parseJson(param1,logger);
            config.friends.updateLocation(_loc6_);
            return true;
         }
         if(param1["class"] == "tbs.srv.data.FriendOnlineData")
         {
            _loc11_ = new FriendOnlineData();
            _loc11_.parseJson(param1,logger);
            _loc16_ = config.friends.updateOnline(_loc11_);
            if(_loc16_)
            {
               _loc17_ = new ChatMsg();
               _loc17_.room = "global";
               _loc17_.username = "FRIEND";
               if(_loc11_.online)
               {
                  _loc17_.msg = _loc16_.display_name + " has logged in.";
               }
               else
               {
                  _loc17_.msg = _loc16_.display_name + " has logged out.";
               }
               chat.handleChatMsg(_loc17_);
            }
            return true;
         }
         if(param1["class"] == "tbs.srv.data.FriendData")
         {
            _loc8_ = new FriendData();
            _loc8_.parseJson(param1,logger);
            config.friends.addFriendData(_loc8_);
            return true;
         }
         if(param1["class"] == "tbs.srv.data.FriendsData")
         {
            config.friends.parseJson(param1,logger);
            return true;
         }
         if(param1["class"] == "tbs.srv.data.PurchasableUnitsData")
         {
            _loc2_ = new PurchasableUnitsData();
            _loc2_.parseJson(param1,logger);
            config.purchasableUnits.update(_loc2_);
            return true;
         }
         if(param1["class"] == "tbs.srv.data.ServerStatusData")
         {
            _loc3_ = ServerStatusData.parse(param1);
            logger.debug("ServerStatusData: " + _loc3_);
            this.playersOnline = _loc3_.session_count;
            dispatchEvent(new GameFsmEvent("GameFsmEvent.PLAYERS_ONLINE"));
            return true;
         }
         if(param1["class"] == "tbs.srv.chat.ChatMsg")
         {
            _loc12_ = ChatMsg.parse(param1);
            chat.handleChatMsg(_loc12_);
            return true;
         }
         if(param1["class"] == "tbs.srv.chat.ChatRoomMsg")
         {
            _loc18_ = new ChatRoomMsg();
            _loc18_.parseJson(param1,logger);
            chat.handleChatRoomMsg(_loc18_);
            return true;
         }
         if(param1["class"] == "tbs.srv.util.SystemMsg")
         {
            _loc4_ = new SystemMsg();
            _loc4_.parseJson(param1,logger);
            config.systemMessage.msg = _loc4_.msg;
            return true;
         }
         if(param1["class"] == "tbs.srv.battle.data.BattleNotification")
         {
            _loc10_ = new BattleNotification();
            _loc10_.parseJson(param1,logger);
            return true;
         }
         if(param1["class"] == "tbs.srv.util.RenownMsg")
         {
            _loc5_ = new RenownMsg();
            _loc5_.parseJson(param1,logger);
            if(_loc5_.timestamp > lastRenownMsgTimestamp)
            {
               lastRenownMsgTimestamp = _loc5_.timestamp;
               logger.debug("RenownMsg: " + _loc5_);
               if(config.accountInfo)
               {
                  config.accountInfo.legend.renown = _loc5_.total;
               }
               if(config.factions)
               {
                  config.factions.legend.renown = _loc5_.total;
               }
            }
            else
            {
               logger.debug("RenownMsg IGNORE OLD: " + _loc5_);
            }
            return true;
         }
         if(param1["class"] == "tbs.srv.util.UnlockData")
         {
            _loc19_ = new UnlockData();
            _loc19_.parseJson(param1,logger);
            config.accountInfo.handleUnlock(_loc19_);
            return true;
         }
         if(param1["class"] == "tbs.srv.util.UnitAddData")
         {
            _loc15_ = new UnitAddData();
            _loc15_.parseJson(param1,logger);
            config.legend.handleUnitAdd(_loc15_);
            return true;
         }
         if(param1["class"] == "tbs.srv.util.CurrencyData")
         {
            _loc7_ = new CurrencyData();
            _loc7_.parseJson(param1,logger);
            if(config.accountInfo)
            {
               config.accountInfo.handleCurrencyData(_loc7_);
            }
            return true;
         }
         if(!super.handleOneMessage(param1))
         {
            if(param1.error_msg != undefined)
            {
               return true;
            }
            return false;
         }
         return true;
      }
      
      override public function startFsm(param1:Object) : void
      {
         super.startFsm(param1);
      }
      
      private function disconnectedDialogCallback(param1:String) : void
      {
         disconnectingDialog = null;
         transitionTo(PreAuthState,current ? current.data : null);
      }
      
      private function maintenanceDialogCallback(param1:String) : void
      {
         disconnectingDialog = null;
         config.context.appInfo.exitGame("Server Maintenance");
      }
      
      private function txnProcessedCallback(param1:HttpAction) : void
      {
         var _loc4_:Boolean = false;
         var _loc2_:Boolean = false;
         var _loc3_:HttpJsonAction = null;
         if(param1.responseCode == 401)
         {
            if(currentClass != PreAuthState && currentClass != AuthState && currentClass != AuthFailedState)
            {
               param1.abort();
               if(!disconnectingDialog)
               {
                  communicator.connected = false;
                  session.credentials.offline = true;
                  disconnectingDialog = config.gameGuiContext.createDialog();
                  disconnectingDialog.openDialog("Disconnected","Disconnected From Server","OK",disconnectedDialogCallback);
               }
               return;
            }
         }
         else if(param1.isMaintenance)
         {
            _loc4_ = param1.response.indexOf("Offline for Maintenance") >= 0;
            _loc2_ = param1.response.indexOf("game_rebooting") >= 0;
            if(_loc4_ || _loc2_)
            {
               param1.abort();
               if(!disconnectingDialog)
               {
                  communicator.connected = false;
                  session.credentials.offline = true;
                  disconnectingDialog = config.gameGuiContext.createDialog();
                  if(_loc4_)
                  {
                     disconnectingDialog.openDialog("Server Offline","The Banner Saga is currently enjoying maintenance.\nCheck back in 5 minutes!","OK",maintenanceDialogCallback);
                  }
                  else
                  {
                     disconnectingDialog.openDialog("Server Rebooting","The Banner Saga is currently rebooting.\nCheck back in 5 minutes!","OK",maintenanceDialogCallback);
                  }
               }
               return;
            }
         }
         if(param1 is HttpJsonAction)
         {
            _loc3_ = param1 as HttpJsonAction;
            if(_loc3_.jsonObject)
            {
               logger.debug("GameFsm INCOMING MSG " + current + ": " + _loc3_.response);
               handleMessage(_loc3_.jsonObject);
            }
         }
      }
      
      private function txnPollCallback() : HttpJsonAction
      {
         if(session.credentials.sessionKey && !session.credentials.offline)
         {
            return new TxnGet(session.credentials,null,logger);
         }
         return null;
      }
      
      public function updateGameLocation(param1:String) : void
      {
         var _loc3_:GameLocationTxn = null;
         if(session.credentials.sessionKey && !session.credentials.offline)
         {
            _loc3_ = new GameLocationTxn(session.credentials,param1,logger);
            _loc3_.send(session.communicator);
         }
         var _loc4_:Number = config.ambienceDef.getLocation(param1);
         var _loc2_:String = config.ambienceDef.getReverb(param1);
         if(_loc4_ != -99999)
         {
            config.soundSystem.ambience = _loc4_;
            config.soundSystem.ambienceEnabled = config.globalPrefs.getPref("option_sfx");
         }
         if(_loc2_)
         {
            config.soundSystem.driver.reverbAmbientPreset(_loc2_);
         }
      }
   }
}

