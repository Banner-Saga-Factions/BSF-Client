package engine.core.http
{
   import engine.core.logging.ILogger;
   import engine.mod.ModBridge; // PATCH: mod-bridge HTTP tap
   import flash.errors.IllegalOperationError;
   import flash.events.TimerEvent;
   import flash.utils.Timer;
   import flash.utils.getQualifiedClassName;
   import flash.utils.getTimer;
   
   public class HttpAction
   {
      
      private static const ALLOW_OFFLINE_MOCK:Boolean = true;
      
      protected var m_url:String;
      
      private var m_callback:Function;
      
      private var _overrideCallback:Function;
      
      private var m_sent:Boolean;
      
      private var m_response:String;
      
      private var m_received:Boolean;
      
      private var m_sendTime:int;
      
      private var m_responseLatency:int;
      
      public var logger:ILogger;
      
      public var success:Boolean;
      
      public var responseCode:int;
      
      public var method:HttpRequestMethod;
      
      public var body:Object;
      
      private var aborted:Boolean;
      
      private var _communicator:HttpCommunicator;
      
      private var _timer:Timer;
      
      public var delay:int;
      
      public var txnName:String;
      
      public var delayStartTime:int;
      
      protected var resendOnFail:Boolean;
      
      protected var resendOnFailDelayMs:int = 2000;
      
      protected var consumedTxn:Boolean;
      
      private var _offlineResponse:String;
      
      private var _offlineResponseStatus:int;
      
      public var offlineTimer:Timer;
      
      public function HttpAction(param1:String, param2:HttpRequestMethod, param3:Object, param4:Function, param5:ILogger)
      {
         super();
         m_url = param1;
         m_callback = param4;
         this.logger = param5;
         this.method = param2;
         this.body = param3;
         txnName = getQualifiedClassName(this);
         txnName = txnName.substr(txnName.lastIndexOf(":") + 1,txnName.length);
      }
      
      public function resend(param1:HttpCommunicator, param2:int) : void
      {
         m_sent = false;
         success = false;
         responseCode = 0;
         aborted = false;
         m_response = null;
         m_received = false;
         m_responseLatency = 0;
         if(_timer)
         {
            _timer.removeEventListener("timerComplete",timerCompleteHandler);
            _timer.stop();
            _timer = null;
         }
         send(param1,_overrideCallback,param2);
      }
      
      public function send(param1:HttpCommunicator, param2:Function = null, param3:int = 0) : void
      {
         if(m_sent)
         {
            throw new IllegalOperationError("Return to sender");
         }
         if(param2 != null)
         {
            _overrideCallback = param2;
         }
         _communicator = param1;
         this.delay = param3;
         if(param3 > 0)
         {
            delayStartTime = getTimer();
            _timer = new Timer(param3,1);
            _timer.addEventListener("timerComplete",timerCompleteHandler);
            _timer.start();
            return;
         }
         doSend();
      }
      
      public function get delayRemainingTime() : int
      {
         var _loc1_:int = 0;
         if(delay > 0)
         {
            _loc1_ = getTimer() - delayStartTime;
            return delay - _loc1_;
         }
         return 0;
      }
      
      private function doSend() : void
      {
         var _loc2_:HttpRequest = null;
         var _loc1_:Array = null;
         m_sendTime = getTimer();
         m_sent = true;
         // PATCH begin: mod-bridge HTTP tap. First txn (AuthTxn at startup)
         // lazily starts the mod host; both calls are no-ops if mods/host.exe
         // is absent. Outbound requests carry the player's own actions
         // (BattleTxn*Send move data), which never appear in responses.
         ModBridge.ensureStarted(logger);
         ModBridge.emitHttpRequest(txnName,url,body);
         // PATCH end
         if(_communicator)
         {
            _loc2_ = _communicator.request(url,method,body,onResponseReceived);
         }
         else
         {
            _loc1_ = url.split("/");
            offlineProcessRequest(_loc1_);
         }
      }
      
      public function forceTimerTimeout() : void
      {
         timerCompleteHandler(null);
      }
      
      private function timerCompleteHandler(param1:TimerEvent) : void
      {
         if(_timer)
         {
            _timer = null;
            doSend();
         }
      }
      
      public function abort() : void
      {
         resendOnFail = false;
         aborted = true;
         m_callback = null;
         if(_timer)
         {
            _timer.stop();
            _timer = null;
         }
      }
      
      protected function handleAbort() : void
      {
      }
      
      public function get url() : String
      {
         return m_url;
      }
      
      public function get response() : String
      {
         if(!m_received)
         {
            throw new IllegalOperationError("No response yet");
         }
         return m_response;
      }
      
      public function get latency() : int
      {
         if(!m_received)
         {
            return getTimer() - m_sendTime;
         }
         return m_responseLatency;
      }
      
      public function get received() : Boolean
      {
         return m_received;
      }
      
      public function get sent() : Boolean
      {
         return m_sent;
      }
      
      public function get shouldProcessResponse() : Boolean
      {
         return responseCode != 404;
      }
      
      public function get debugResponseString() : String
      {
         return m_response ? m_response.substring(0,500).split("\n").join("") : null;
      }
      
      protected function onResponseReceived(param1:String, param2:Boolean, param3:int) : void
      {
         var _loc4_:String = null;
         if(aborted)
         {
            logger.debug("Ignoring aborted response for " + this + " " + param3 + ": " + param1);
            return;
         }
         m_response = param1;
         if(!param2)
         {
            _loc4_ = txnName + " onResponseReceived ERROR url=" + url + " ok=" + param2 + " status=" + param3 + " response=" + debugResponseString;
            logger.info(_loc4_);
         }
         if(m_received)
         {
            throw new IllegalOperationError("Redundant response");
         }
         m_responseLatency = getTimer() - m_sendTime;
         m_response = param1;
         m_received = true;
         this.success = param2;
         this.responseCode = param3;
         // PATCH begin: mod-bridge HTTP tap. m_response is the verbatim wire
         // string - emitted before any parsing/processing so the host sees
         // every server reply (JSON or not), including error bodies.
         ModBridge.emitHttpResponse(txnName,url,responseCode,success,m_response);
         // PATCH end
         if(shouldProcessResponse)
         {
            handleResponseProcessing();
         }
         if(communicator && (!consumedTxn || isMaintenance))
         {
            communicator.onHttpTxnResponseProcessed(this);
         }
         if(null != _overrideCallback)
         {
            _overrideCallback(this);
         }
         else
         {
            issueCallback();
         }
         if(received && !success)
         {
            if(resendOnFail)
            {
               if(canRetry)
               {
                  logger.error("Failed to " + this + " with code " + responseCode + ", retrying");
                  resend(communicator,resendOnFailDelayMs);
               }
               else
               {
                  logger.error("Failed to " + this + " with code " + responseCode + ", WILL NOT RETRY");
               }
            }
         }
      }
      
      public function issueCallback() : void
      {
         if(!m_received)
         {
            throw new IllegalOperationError("Cannot issue a callback prior to a response!");
         }
         if(null != m_callback)
         {
            m_callback(this);
         }
      }
      
      protected function handleResponseProcessing() : void
      {
      }
      
      protected function offlineProcessRequest(param1:Array) : void
      {
         setOfflineResponse(null,404);
      }
      
      public function setOfflineResponse(param1:Object, param2:int) : void
      {
         var _loc3_:String = null;
         if(param1 is String)
         {
            _loc3_ = param1 as String;
         }
         else if(param1)
         {
            _loc3_ = JSON.stringify(param1);
         }
         _offlineResponse = _loc3_;
         this._offlineResponseStatus = param2;
         offlineTimer = new Timer(100,1);
         offlineTimer.addEventListener("timerComplete",offlineTimerHandler);
         offlineTimer.start();
      }
      
      protected function offlineTimerHandler(param1:TimerEvent) : void
      {
         var _loc2_:Boolean = _offlineResponseStatus >= 200 && _offlineResponseStatus < 300;
         onResponseReceived(_offlineResponse,_loc2_,_offlineResponseStatus);
         offlineTimer = null;
      }
      
      public function get offlineResponse() : String
      {
         return _offlineResponse;
      }
      
      public function get overrideCallback() : Function
      {
         return _overrideCallback;
      }
      
      public function set overrideCallback(param1:Function) : void
      {
         _overrideCallback = param1;
      }
      
      public function get communicator() : HttpCommunicator
      {
         return _communicator;
      }
      
      public function set communicator(param1:HttpCommunicator) : void
      {
         _communicator = param1;
      }
      
      public function get canRetry() : Boolean
      {
         if(received && !success && !isMaintenance)
         {
            return responseCode == 0 || responseCode == 404 || responseCode >= 500;
         }
         return false;
      }
      
      public function get isMaintenance() : Boolean
      {
         if(responseCode == 503)
         {
            return response.indexOf("Offline for Maintenance") >= 0 || response.indexOf("game_rebooting") >= 0;
         }
         return false;
      }
   }
}

