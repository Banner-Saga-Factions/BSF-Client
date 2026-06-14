package game.cfg
{
   import engine.core.cmd.Cmd;
   import engine.core.cmd.CmdExec;
   import engine.core.cmd.KeyBinder;
   import game.session.GameFsm;

   public class GameKeyBinder extends KeyBinder
   {
      
      public function GameKeyBinder(param1:GameConfig, param2:int)
      {
         super(param1.shell,param1.logger);
         bind(true,false,true,82,new Cmd("toggle_redraw_regions",wrap(param1.context.appInfo.toggleRedrawRegions)),"KeyBindGroup.COMBAT");
         // Dev trigger (Ctrl+Shift+A): launch an offline player-vs-AI battle (mirror of the player's
         // active party) with no host. Same entry point as the ModBridge "start_ai_battle" command.
         // Reads config.fsm at keypress time, so it is safe regardless of construction order.
         var cfg:GameConfig = param1;
         bind(true,false,true,65,new Cmd("debug_start_ai_battle",wrap(function():void
         {
            cfg.fsm.startAiBattle(false);
         })),"KeyBindGroup.COMBAT");
         if(param2 == 0)
         {
            bind(true,false,true,70,new Cmd("toggle_fullscreen",wrap(param1.context.appInfo.toggleFullscreen)),"KeyBindGroup.COMBAT");
         }
      }
      
      public function wrap(param1:Function) : Function
      {
         var f:Function = param1;
         return function(param1:CmdExec):void
         {
            f();
         };
      }
   }
}

