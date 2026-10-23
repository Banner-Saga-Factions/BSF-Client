package game.session.actions
{
   import engine.core.http.HttpJsonAction;
   import engine.core.http.HttpRequestMethod;
   import engine.core.logging.ILogger;

   /**
    * BSF patch (#2): asks the server whether the player has finished the Discord step in the
    * browser. The answer is 200 with status pending / ready / failed / expired, so the game's
    * own automatic re-send (404 and 5xx only) never starts.
    */
   public class DiscordPollTxn extends HttpJsonAction
   {

      public function DiscordPollTxn(key:String, callback:Function, logger:ILogger)
      {
         // The key goes in a JSON body, never the address; sent any other way the server
         // cannot read it and answers "expired".
         super("login/discord/handoff/poll",HttpRequestMethod.POST,{"key":key},callback,logger);
      }

      override protected function handleJsonResponseProcessing() : void
      {
         // Handled here, so GameFsm does not log a reply every two seconds.
         if(jsonObject)
         {
            consumedTxn = true;
         }
      }

      public function get status() : String
      {
         return jsonObject ? jsonObject.status : null;
      }

      public function get serverMessage() : String
      {
         return jsonObject ? jsonObject.message : null;
      }
   }
}
