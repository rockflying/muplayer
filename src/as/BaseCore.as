package {
    import flash.display.Sprite;
    import flash.events.*;
    import flash.media.SoundTransform;
    import flash.system.Security;
    import flash.utils.Timer;

    public class BaseCore extends Sprite implements IEngine {
        // JS回调
        private var jsInstance:String = '';
        private var errTimes:int = 0;

        protected var playerTimer:Timer;
        protected var stf:SoundTransform;

        // 实例属性
        protected var _volume:uint = 80;               // 音量(0-100)，默认80
        protected var _mute:Boolean = false;           // 静音状态，默认flase
        protected var _state:int = State.STOP;         // 播放状态
        protected var _muteVolume:uint;                // 静音时的音量
        protected var _url:String;                     // 外部文件地址
        protected var _length:uint;                    // 音频总长度(ms)
        protected var _position:uint;                  // 当前播放进度(ms)
        protected var _loadedPct:Number;               // 载入进度百分比[0-1]
        protected var _positionPct:Number;             // 播放进度百分比[0-1]
        protected var _pausePosition:Number;           // 暂停时的播放进度(ms)
        protected var _bytesTotal:uint;                // 外部文件总字节
        protected var _bytesLoaded:uint;               // 已载入字节

        // 最小缓冲时间(ms)
        // MP3 数据保留在Sound对象缓冲区中的最小毫秒数。
        // 在开始回放以及在网络中断后继续回放之前，Sound 对
        // 象将一直等待直至至少拥有这一数量的数据为止。
        // 默认值为1000毫秒。
        private var _bufferTime:uint = 5000;

        public function BaseCore() {
            function check(e:Event = null):void {
                if (stage.stageWidth > 0) {
                    removeEventListener(Event.ENTER_FRAME, check);
                    init();
                }
            }
            addEventListener(Event.ENTER_FRAME, check);
        }

        public function init():void {
            Security.allowDomain('*');
            Security.allowInsecureDomain('*');
            loadFlashVars(loaderInfo.parameters);
            stf = new SoundTransform(_volume / 100, 0);
        }

        protected function callJS(fn:String, data:Object = undefined):void {
            Utils.callJS(jsInstance + fn, data);
        }

        protected function loadFlashVars(p:Object):void {
            jsInstance = escape(p['_instanceName']);
            if (p['_buffertime']) {
                _bufferTime = ~~p['_buffertime'];
            }
        }

        protected function onPlayComplete(e:Event = null):void {
            // 保证length和positionPct赋值正确。
            onPlayTimer();
            f_pause()
            setState(State.END);
        }

        protected function onPlayTimer(e:TimerEvent = null):void {}

        protected function handleErr(e:* = null):void {
            // 出错时默认跳歌重试，再次出错就交由外部JS处理，比如切换播放内核等。
            if (errTimes++) {
                onPlayComplete();
            } else {
                errTimes = 0;
                f_stop();
                reset();
                callJS(Consts.SWF_ON_ERR, e);
            }
        }

        public function getData(k:String):* {
            var fn:String = 'get' + k.substr(0, 1).toUpperCase() + k.slice(1);
            if (this[fn]) {
                return this[fn]();
            }
        }

        public function setData(k:String, v:*):* {
            var fn:String = 'set' + k.substr(0, 1).toUpperCase() + k.slice(1);
            if (this[fn]) {
                return this[fn](v);
            }
        }

        public function getState():int {
            return _state;
        }

        public function setState(st:int):void {
            if (_state !== st && State.validate(st)) {
                _state = st;
                callJS(Consts.SWF_ON_STATE_CHANGE, st);
            }
        }

        public function getBufferTime():uint {
            return _bufferTime;
        }

        public function getMute():Boolean {
            return _mute;
        }

        public function setMute(m:Boolean):void {
            if (m) {
                _muteVolume = _volume;
                setVolume(0);
            } else {
                setVolume(_muteVolume || _volume);
            }
            _mute = m;
        }

        public function getVolume():uint {
            return _volume;
        }

        public function setVolume(v:uint):Boolean {
            if (v < 0 || v > 100) {
                return false;
            }
            _volume = v;
            stf.volume = v / 100;
            return true;
        }

        public function getUrl():String {
            return _url;
        }

        public function getLength():uint {
            return _length;
        }

        public function getPosition():uint {
            return _position;
        }

        public function getLoadedPct():Number {
            return _loadedPct;
        }

        // positionPct和loadedPct都在JS层按需获取，不在
        // AS层主动派发，这样简化逻辑，节省事件开销。
        public function getPositionPct():Number {
            return _positionPct;
        }

        public function getBytesTotal():uint {
            return _bytesTotal;
        }

        public function getBytesLoaded():uint {
            return _bytesLoaded;
        }

        public function reset():void {
            _url = '';
            _length = 0;
            _position = 0;
            _loadedPct = 0;
            _positionPct = 0;
            _pausePosition = 0;
            _bytesTotal = 0;
            _bytesLoaded = 0;
        }

        public function f_load(url:String):void {}

        public function f_play(p:Number = 0):void {
            if (!playerTimer) {
                playerTimer = new Timer(Consts.TIMER_INTERVAL);
                playerTimer.addEventListener(TimerEvent.TIMER, onPlayTimer);
                playerTimer.start();
            }
        }

        public function f_pause():void {}

        public function f_stop(p:Number = 0):void {
            _pausePosition = p;
            if (playerTimer) {
                playerTimer.removeEventListener(TimerEvent.TIMER, onPlayTimer);
                playerTimer.stop();
                playerTimer = null;
            }
            setState(p && State.PAUSE || State.STOP);
        }
    }
}
