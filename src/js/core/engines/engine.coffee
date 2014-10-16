do (root = @, factory = (cfg, utils, Events, EngineCore, AudioCore, FlashMP3Core, FlashMP4Core) ->
    {EVENTS, STATES} = cfg.engine
    timerResolution = cfg.timerResolution
    extReg = /\.(\w+)(\?.*)?$/

    class Engine
        # 隐藏容器, 用于容纳swf和audio等标签
        # 参考: http://stackoverflow.com/questions/1168222/hiding-showing-a-swf-in-a-div
        @el: '<div id="muplayer_container_{{DATETIME}}" style="width: 1px; height: 1px; overflow: hidden"></div>'

        defaults:
            engines: `[
                //>>excludeStart("FlashCoreExclude", pragmas.FlashCoreExclude);
                {
                    constructor: FlashMP3Core
                },
                {
                    constructor: FlashMP4Core
                },
                //>>excludeEnd("FlashCoreExclude");
                {
                    constructor: AudioCore
                }
            ]`

        constructor: (options) ->
            @opts = $.extend({}, @defaults, options)
            @_initEngines()

        _initEngines: ->
            @engines = []
            opts = @opts
            $el = $(Engine.el.replace(/{{DATETIME}}/g, +new Date())).appendTo('body')

            for engine, i in opts.engines
                constructor = engine.constructor
                args = engine.args or {}
                args.baseDir = opts.baseDir
                args.$el = $el

                try
                    constructor = eval(constructor) unless $.isFunction(constructor)
                    engine = new constructor(args)
                catch
                    throw "Missing constructor: #{String(engine.constructor)}"

                if engine._test()
                    @engines.push(engine)

            if @engines.length
                @setEngine(@engines[0])
            else
                # 没有适配的内核时就初始化EngineCore这个基类，以防调用报错
                @setEngine(new EngineCore)

        setEngine: (engine) ->
            # HACK: 怀疑aralejs事件库有潜在bug, 内核切换时（比如从FlashMP4Core切到FlashMP3Core），
            # statechangeHandle有可能派发连续的重复事件，导致STATES.END被重复触发引发跳歌。
            # 升级事件库后有其他问题，暂时通过lastE标记解决。后续可以更新事件库或深入研究下。
            @_lastE = {}

            statechangeHandle = (e) =>
                if e.oldState is @_lastE.oldState and e.newState is @_lastE.newState
                    return
                @_lastE =
                    oldState: e.oldState
                    newState: e.newState
                @trigger(EVENTS.STATECHANGE, e)
            positionHandle = (pos) =>
                @trigger(EVENTS.POSITIONCHANGE, pos)
            progressHandle = (progress) =>
                @trigger(EVENTS.PROGRESS, progress)
            errorHandle = (e) =>
                @trigger(EVENTS.ERROR, e)

            bindEvents = (engine) ->
                engine.on(EVENTS.STATECHANGE, statechangeHandle)
                    .on(EVENTS.POSITIONCHANGE, positionHandle)
                    .on(EVENTS.PROGRESS, progressHandle)
                    .on(EVENTS.ERROR, errorHandle)
            unbindEvents = (engine) ->
                engine.off(EVENTS.STATECHANGE, statechangeHandle)
                    .off(EVENTS.POSITIONCHANGE, positionHandle)
                    .off(EVENTS.PROGRESS, progressHandle)
                    .on(EVENTS.ERROR, errorHandle)

            unless @curEngine
                @curEngine = bindEvents(engine)
            else if @curEngine isnt engine
                oldEngine = @curEngine
                unbindEvents(oldEngine).reset()
                @curEngine = bindEvents(engine)
                @curEngine.setVolume(oldEngine.getVolume())
                    .setMute(oldEngine.getMute())

        canPlayType: (type) ->
            $.inArray(type, @getSupportedTypes()) isnt -1

        getSupportedTypes: ->
            types = []
            for engine in @engines
                types = types.concat(engine.getSupportedTypes())
            types

        switchEngineByType: (type) ->
            match = false

            for engine in @engines
                if engine.canPlayType(type)
                    @setEngine(engine)
                    match = true
                    break

            # 如果没有匹配到则用默认类型适配。
            unless match
                @setEngine(@engines[0])

        reset: ->
            @curEngine.reset()
            @

        setUrl: (url) ->
            if extReg.test(url)
                ext = RegExp.$1.toLocaleLowerCase()

            if @canPlayType(ext)
                @switchEngineByType(ext) unless @curEngine.canPlayType(ext)
            else
                throw new Error("Can not play with: #{ext}")

            @curEngine.setUrl(url)
            @

        getUrl: ->
            @curEngine.getUrl()

        play: ->
            @curEngine.play()
            @

        pause: ->
            @curEngine.pause()
            @trigger(EVENTS.POSITIONCHANGE, @getCurrentPosition())
            @setState(STATES.PAUSE)
            @

        stop: ->
            @curEngine.stop()
            @trigger(EVENTS.POSITIONCHANGE, 0)
            @setState(STATES.STOP)
            @

        setState: (st) ->
            @curEngine.setState(st)
            @

        getState: ->
            @curEngine.getState()

        setMute: (mute) ->
            @curEngine.setMute(!!mute)
            @

        getMute: ->
            @curEngine.getMute()

        # 0 <= volume <= 100
        setVolume: (volume) ->
            if $.isNumeric(volume) and volume >= 0 and volume <= 100
                @curEngine.setVolume(volume)
            @

        getVolume: ->
            @curEngine.getVolume()

        # 设置播放进度(单位毫秒)
        setCurrentPosition: (ms) ->
            ms = ~~ms
            @curEngine.setCurrentPosition(ms)
            @

        getCurrentPosition: ->
            @curEngine.getCurrentPosition()

        # 音频下载的百分比, 取值: 0 ~ 1
        getLoadedPercent: ->
            @curEngine.getLoadedPercent()

        # 音频总时长, 单位毫秒
        getTotalTime: ->
            @curEngine.getTotalTime()

        getEngineType: ->
            @curEngine.engineType

        # 当前内核的播放状态: play, pause, pre-buffer等
        getState: ->
            @curEngine.getState()

    Events.mixTo(Engine)
    Engine
) ->
    if typeof exports is 'object'
        module.exports = factory()
    else if typeof define is 'function' and define.amd
        `define([
            'muplayer/core/cfg'
            , 'muplayer/core/utils'
            , 'muplayer/lib/events'
            , 'muplayer/core/engines/engineCore'
            , 'muplayer/core/engines/audioCore'
            //>>excludeStart("FlashCoreExclude", pragmas.FlashCoreExclude);
            , 'muplayer/core/engines/flashMP3Core'
            , 'muplayer/core/engines/flashMP4Core'
            //>>excludeEnd("FlashCoreExclude");
        ], factory)`
    else
        `root._mu.Engine = factory(
            _mu.cfg
            , _mu.utils
            , _mu.Events
            , _mu.EngineCore
            , _mu.AudioCore
            //>>excludeStart("FlashCoreExclude", pragmas.FlashCoreExclude);
            , _mu.FlashMP3Core
            , _mu.FlashMP4Core
            //>>excludeEnd("FlashCoreExclude");
        )`
