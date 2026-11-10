package game.gui.page
{
   import engine.core.cmd.Cmd;
   import engine.core.cmd.CmdExec;
   import engine.core.locale.LocaleCategory;
   import engine.resource.MovieClipResource;
   import engine.resource.event.ResourceLoadedEvent;
   import flash.display.DisplayObject;
   import flash.display.MovieClip;
   import flash.events.Event;
   import flash.geom.Rectangle;
   import game.cfg.GameConfig;
   import game.gui.ButtonWithIndex;
   import game.gui.IGuiStrandOptions;
   import game.gui.IGuiStrandOptionsListener;
   import game.session.states.DiscordSignIn;

   // BSF patch (BSF-Client #96, Wave 2): adds a "Signin: Steam / Discord" button to the town
   // options panel (the hammer icon, or Esc). Clicking it switches the saved way to sign in, which
   // the game uses from the next launch. The panel's own code lives in the game-art file
   // gui/strand_options.swf, which our patches cannot change, so the button is added from here
   // (docs/architecture.md, "Adding to a resource SWF's panel without editing it"). Everything else is the shipped original.
   public class TownPage extends ScenePage implements IGuiStrandOptionsListener
   {

      /** The five text buttons are drawn at this size, so that they fit the space the four stock
       *  buttons use (the panel's frame and divider are one fixed drawing). */
      private static const SIGNIN_LAYOUT_SCALE:Number = 0.85;

      private var signInButton:ButtonWithIndex;

      private var chatHelper:GlobalChatHelper;
      
      private var guidepost:String;
      
      private var guidepostClick:String;
      
      private var guidepostPrefKey:String;
      
      private var strandOptionsMcr:MovieClipResource;
      
      private var _options:IGuiStrandOptions;
      
      private var cmd_town_escape:Cmd;
      
      public function TownPage(param1:GameConfig)
      {
         cmd_town_escape = new Cmd("town_escape",cmdEscapeFunc);
         super(param1);
      }
      
      private function checkTownChatEnabled() : void
      {
         if(sceneState && sceneState.chatEnabled)
         {
            if(!chatHelper)
            {
               chatHelper = new GlobalChatHelper(this,config,"global");
            }
         }
         else if(chatHelper)
         {
            chatHelper.cleanup();
            chatHelper = null;
         }
      }
      
      override protected function chatEnabledHandler(param1:Event) : void
      {
         super.chatEnabledHandler(param1);
         checkTownChatEnabled();
      }
      
      override public function cleanup() : void
      {
         super.cleanup();
         config.keybinder.unbind(cmd_town_escape);
         if(chatHelper)
         {
            chatHelper.cleanup();
            chatHelper = null;
         }
      }
      
      override protected function handleStart() : void
      {
         super.handleStart();
         checkTownChatEnabled();
         strandOptionsMcr = getGuiPageResource("strand_options.swf/gui.strand.options");
         strandOptionsMcr.addResourceListener(optionsLoadedHandler);
         config.keybinder.bind(false,false,false,27,cmd_town_escape,"KeyBindGroup.TOWN");
      }
      
      override protected function resizeHandler() : void
      {
         super.resizeHandler();
         if(chatHelper)
         {
            chatHelper.resize();
         }
         if(_options)
         {
            _options.setSize(width,height);
         }
      }
      
      override protected function handleDelayStart() : void
      {
         super.handleDelayStart();
         if(chatHelper)
         {
            chatHelper.bringToFront();
         }
         if(_options)
         {
            this.addChild(_options.movieClip);
         }
         bringContainerToFront();
      }
      
      override protected function handleLandscapeClick(param1:String) : void
      {
         sceneState.handleLandscapeClick(param1);
      }
      
      private function optionsLoadedHandler(param1:ResourceLoadedEvent) : void
      {
         var _loc2_:Boolean = false;
         if(strandOptionsMcr.ok)
         {
            _options = strandOptionsMcr.movieClip as IGuiStrandOptions;
            _loc2_ = chatHelper ? chatHelper.enabled : false;
            config.context.locale.translateDisplayObjects(LocaleCategory.GUI,_options.movieClip);
            _options.init(config.gameGuiContext,this);
            config.context.locale.translateDisplayObjects(LocaleCategory.GUI,_options.movieClip);
            try
            {
               addSignInButton();
            }
            catch(e:Error)
            {
               // A panel that doesn't look as expected must not cost the player the town.
               config.logger.error("TownPage could not add the sign-in button: " + e.message);
            }
            this.addChild(_options.movieClip);
         }
      }

      /** Adds the "Signin" button above Quit, as a new copy of the panel's own button art. */
      private function addSignInButton() : void
      {
         // Sign-in ignores the saved choice in kiosk mode and on a --steam_id or --steam false
         // launch (PreAuthState), so there the button would promise a change that never happens.
         if(config.runMode.autologin || config.options.overrideSteamId || DiscordSignIn.steamTurnedOff)
         {
            return;
         }
         // Read through the panel's own field, not by name: init hides the menu and takes it off
         // the panel's display list (GuiUtil.updateDisplayList), so a lookup by name finds nothing.
         var menu:MovieClip = Object(_options.movieClip).option_menu as MovieClip;
         if(!menu)
         {
            config.logger.error("TownPage: no option_menu in the options panel; no sign-in button");
            return;
         }
         var resume:ButtonWithIndex = menu.getChildByName("button$resume") as ButtonWithIndex;
         var news:ButtonWithIndex = menu.getChildByName("button$news") as ButtonWithIndex;
         var fullscreen:ButtonWithIndex = menu.getChildByName("button$fullscreen") as ButtonWithIndex;
         var quit:ButtonWithIndex = menu.getChildByName("button$quit") as ButtonWithIndex;
         if(!resume || !news || !fullscreen || !quit)
         {
            config.logger.error("TownPage: a stock options button is missing; no sign-in button");
            return;
         }
         // Resume, News, Fullscreen and Quit are all one exported design in strand_options.swf
         // (gui.battle.option.button), so making a new one of News's own class gives the same art.
         var buttonClass:Class = Object(news).constructor as Class;
         signInButton = new buttonClass() as ButtonWithIndex;
         if(!signInButton)
         {
            config.logger.error("TownPage: the copied button is not a game button; no sign-in button");
            return;
         }
         // No "$" in the name, so the game's translator leaves the label alone.
         signInButton.name = "signin_button";
         signInButton.context = config.gameGuiContext;
         signInButton.scaleTextToFit = true;
         signInButton.setDownFunction(onSignInClicked);
         updateSignInLabel();
         menu.addChildAt(signInButton,menu.getChildIndex(quit));
         layOutOptionButtons(menu,[resume,news,fullscreen,signInButton,quit]);
      }

      /** Spreads the buttons evenly, smaller, between the top of the first stock button and the
       *  bottom of the last one. Uses each button's drawn edges, because the art sits away from
       *  the button's own anchor point and would drift if only scaled. */
      private function layOutOptionButtons(menu:MovieClip, buttons:Array) : void
      {
         var first:Rectangle = (buttons[0] as DisplayObject).getBounds(menu);
         var last:Rectangle = (buttons[buttons.length - 1] as DisplayObject).getBounds(menu);
         var top:Number = first.top;
         var centreX:Number = last.left + last.width / 2;
         var scaledHeight:Number = last.height * SIGNIN_LAYOUT_SCALE;
         var pitch:Number = (last.bottom - top - scaledHeight) / (buttons.length - 1);
         var i:int = 0;
         var button:DisplayObject = null;
         var drawn:Rectangle = null;
         for(i = 0; i < buttons.length; i++)
         {
            button = buttons[i] as DisplayObject;
            button.scaleX = button.scaleY = SIGNIN_LAYOUT_SCALE;
            drawn = button.getBounds(menu);
            button.x += centreX - (drawn.left + drawn.width / 2);
            button.y += top + i * pitch - drawn.top;
         }
      }

      private function updateSignInLabel() : void
      {
         if(signInButton)
         {
            signInButton.buttonText = DiscordSignIn.savedRouteIsDiscord(config) ? "Signin: Discord" : "Signin: Steam";
         }
      }

      private function onSignInClicked(param1:ButtonWithIndex) : void
      {
         var toDiscord:Boolean = !DiscordSignIn.savedRouteIsDiscord(config);
         DiscordSignIn.saveRoute(config,toDiscord ? DiscordSignIn.ROUTE_DISCORD : DiscordSignIn.ROUTE_STEAM,config.logger);
         updateSignInLabel();
         config.gameGuiContext.createDialog().openDialog("Sign in changed","From the next launch, the game signs in with " + (toDiscord ? "Discord" : "Steam") + ". Steam and Discord are separate accounts.","OK");
      }

      public function guiOptionsSetMusic(param1:Boolean) : void
      {
         config.soundSystem.musicEnabled = param1;
         config.globalPrefs.setPref("option_music",param1);
      }
      
      public function guiOptionsSetSfx(param1:Boolean) : void
      {
         config.soundSystem.sfxEnabled = param1;
         config.soundSystem.ambienceEnabled = param1;
         config.globalPrefs.setPref("option_sfx",param1);
      }
      
      public function guiOptionsToggleFullcreen() : void
      {
         config.context.appInfo.toggleFullscreen();
      }
      
      public function guiOptionsNews() : void
      {
         config.showNews();
      }
      
      public function guiOptionsQuitGame() : void
      {
         config.context.appInfo.exitGame("options");
      }
      
      public function cmdEscapeFunc(param1:CmdExec) : void
      {
         if(!config.pageManager.escapeFromMarket())
         {
            if(_options)
            {
               _options.toggleOptions();
            }
         }
      }
   }
}

