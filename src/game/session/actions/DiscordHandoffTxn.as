package game.session.actions
{
   import engine.core.http.HttpJsonAction;
   import engine.core.http.HttpRequestMethod;
   import engine.core.logging.ILogger;

   /**
    * BSF patch (#2): asks the server for a Discord hand-off — a waiting sign-in with a short
    * code the player checks in the browser and a secret key only the game keeps. Server side:
    * bsf-server/docs/serverEndpoints.md, "Discord sign-in (hand-off) Endpoints".
    */
   public class DiscordHandoffTxn extends HttpJsonAction
   {

      public function DiscordHandoffTxn(callback:Function, logger:ILogger)
      {
         // An empty JSON body rather than none: AIR sends a POST with no body as a GET.
         super("login/discord/handoff",HttpRequestMethod.POST,{},callback,logger);
      }

      override protected function handleJsonResponseProcessing() : void
      {
         // Marked as handled so GameFsm does not write the reply, which carries the key, to
         // the game's log ("GameFsm INCOMING MSG"). AuthTxn does the same with its reply.
         if(jsonObject)
         {
            consumedTxn = true;
         }
      }

      public function get code() : String
      {
         return jsonObject ? jsonObject.code : null;
      }

      public function get key() : String
      {
         return jsonObject ? jsonObject.key : null;
      }

      public function get pageUrl() : String
      {
         return jsonObject ? jsonObject.url : null;
      }

      /** The server's reason when it will not start one (a 429 answers {error}). */
      public function get refusal() : String
      {
         if(jsonObject && jsonObject.error)
         {
            return jsonObject.error;
         }
         return message;
      }
   }
}
