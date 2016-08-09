describe 'Turbolinks', ->

  createTurboNodule = ->
    $nodule = $("<div>").attr("id", "turbo-area").attr("refresh", "turbo-area")
    return $nodule[0]

  url_for = (slug) ->
    window.location.origin + slug

  beforeEach ->
    @server = sinon.fakeServer.create()
    $("script").attr("data-turbolinks-eval", false)
    $("#mocha").attr("refresh-never", true)
    @replaceStateStub = stub(Turbolinks, "replaceState")
    @pushStateStub = stub(Turbolinks, "pushState")
    document.body.appendChild(createTurboNodule())

  afterEach ->
    @server.restore()
    @pushStateStub.restore()
    @replaceStateStub.restore()
    $("#turbo-area").remove()

  html_one = """
    <!doctype html>
    <html>
      <head>
        <title>Hi there!</title>
      </head>
      <body>
        <div>YOLO</div>
        <div id="turbo-area" refresh="turbo-area">Hi bob</div>
      </body>
    </html>
  """

  html_with_script_in_head = """
    <!doctype html>
    <html>
      <head>
        <script src='merp' data-turbolinks-track="true"></script>
        <title>Hi there!</title>
      </head>
      <body>
        <div>Merp</div>
        <div id="turbo-area" refresh="turbo-area">derp</div>
      </body>
    </html>
  """

  html_with_link_in_head = """
    <!doctype html>
    <html>
      <head>
        <link href='merp' data-turbolinks-track="true"></link>
        <title>Hi there!</title>
      </head>
      <body>
        <div>Merp</div>
        <div id="turbo-area" refresh="turbo-area">derp</div>
      </body>
    </html>
  """

  script_response = """
    <!doctype html>
    <html>
      <head>
        <title>Hi</title>
      </head>
      <body>
        <script id="turbo-area" refresh="turbo-area">globalStub()</script>
      </body>
    </html>
  """

  script_response_turbolinks_eval_false = """
    <!doctype html>
    <html>
      <head>
        <title>Hi</title>
      </head>
      <body>
        <script data-turbolinks-eval="false" id="turbo-area" refresh="turbo-area">globalStub()</script>
      </body>
    </html>
  """

  response_with_refresh_always = """
    <!doctype html>
    <html>
      <head>
        <title>Hi</title>
      </head>
      <body>
        <div id="div1" refresh="div1">
          <div id="div2" refresh-always>Refresh-always</div>
        </div>
      </body>
    </html>
  """

  it 'is defined', ->
    assert Turbolinks

  describe '#visit', ->
    it 'returns if pageChangePrevented', ->
      listener = (event) ->
        event.preventDefault()
        assert.equal '/some_request', event.data

      window.addEventListener('page:before-change', listener)

      Turbolinks.visit "/some_request", {partialReplace: true, onlyKeys: ['turbo-area']}
      assert.equal 0, @server.requests.length

      window.removeEventListener('page:before-change', listener)

    it 'supports passing request headers', ->
      @server.respondWith([200, { "Content-Type": "text/html" }, "<html>Hello World</html>"]);

      Turbolinks.visit "/some_request", {headers: {'foo': 'bar', 'fizz': 'buzz'}}
      @server.respond()

      assert.equal 1, @server.requests.length
      assert.equal 'bar', @server.requests[0].requestHeaders['foo']
      assert.equal 'buzz', @server.requests[0].requestHeaders['fizz']

    describe 'with partial page replacement', ->
      it 'uses just the part of the response body we supply', ->
        @server.respondWith([200, { "Content-Type": "text/html" }, html_one]);

        Turbolinks.visit "/some_request", {partialReplace: true, onlyKeys: ['turbo-area']}
        @server.respond()

        assert.equal "Hi there!", document.title
        assert.equal -1, document.body.textContent.indexOf("YOLO")
        assert document.body.textContent.indexOf("Hi bob") > 0
        assert @pushStateStub.calledOnce
        assert @pushStateStub.calledWith({turbolinks: true, url: url_for("/some_request")}, "", url_for("/some_request"))
        assert.equal 0, @replaceStateStub.callCount

      it 'doesn\'t update the window state if updatePushState is false', ->
        @server.respondWith([200, { "Content-Type": "text/html" }, html_one]);

        Turbolinks.visit "/some_request", {partialReplace: true, onlyKeys: ['turbo-area'], updatePushState: false}
        @server.respond()

        assert.equal "Hi there!", document.title
        assert.equal -1, document.body.textContent.indexOf("YOLO")
        assert document.body.textContent.indexOf("Hi bob") > 0
        assert @pushStateStub.notCalled
        assert @replaceStateStub.notCalled

      it 'calls a user-supplied callback', ->
        @server.respondWith([200, { "Content-Type": "text/html" }, html_one]);

        your_callback = stub()
        Turbolinks.visit "/some_request", {partialReplace: true, onlyKeys: ['turbo-area'], callback: your_callback}
        @server.respond()

        assert your_callback.calledOnce

      it 'script tags are evaluated when they are the subject of a partial replace', ->
        window.globalStub = stub()
        @server.respondWith([200, { "Content-Type": "text/html" }, script_response]);

        Turbolinks.visit "/some_request", {partialReplace: true, onlyKeys: ['turbo-area']}
        @server.respond()
        assert globalStub.calledOnce

      it 'script tags are not evaluated if they have [data-turbolinks-eval="false"]', ->
        window.globalStub = stub()
        @server.respondWith([200, { "Content-Type": "text/html" }, script_response_turbolinks_eval_false]);

        Turbolinks.visit "/some_request", {partialReplace: true, onlyKeys: ['turbo-area']}
        @server.respond()
        assert.equal 0, globalStub.callCount

      it 'triggers the page:load event with a list of nodes that are new (freshly replaced)', ->
        $(document).one 'page:load', (event) ->
          ev = event.originalEvent
          assert.equal true, ev.data instanceof Array
          assert.equal 1, ev.data.length
          node = ev.data[0]

          assert.equal "turbo-area", node.id
          assert.equal "turbo-area", node.getAttribute('refresh')

        @server.respondWith([200, { "Content-Type": "text/html" }, html_one]);

        Turbolinks.visit "/some_request", {partialReplace: true, onlyKeys: ['turbo-area']}
        @server.respond()

        $(document).off 'page:load'

      it 'does not trigger the page:before-partial-replace event more than once', ->
        handler = stub()
        $(document).on 'page:before-partial-replace', ->
          handler()
          assert handler.calledOnce

        @server.respondWith([200, { "Content-Type": "text/html" }, html_one]);

        Turbolinks.visit "/some_request", {partialReplace: true, onlyKeys: ['turbo-area']}
        @server.respond()

        $(document).off 'page:before-partial-replace'

      it 'replaces and passes through the outermost nodes if a series of nodes got replaced', ->
        currentBody = """
          <div id="div1" refresh="div1">
            <div id="div2" refresh-always>Refresh-always</div>
          </div>
        """

        $("body").append($(currentBody))

        $(document).on 'page:before-partial-replace', (ev) ->
          nodes = ev.originalEvent.data
          assert.equal 2, nodes.length
          assert.equal 'div2', nodes[0].id
          assert.equal 'div1', nodes[1].id

        $(document).on 'page:load', (ev) ->
          nodes = ev.originalEvent.data
          assert.equal 1, nodes.length
          assert.equal 'div1', nodes[0].id

        @server.respondWith([200, { "Content-Type": "text/html" }, response_with_refresh_always])

        Page.refresh(onlyKeys: ['div1'])
        @server.respond()

        $(document).off 'page:before-partial-replace'
        $(document).off 'page:load'

        $("#div1").remove()

      it 'does not trigger a full refresh when a new script is in the head', ->
        @server.respondWith([200, { "Content-Type": "text/html" }, html_with_script_in_head])

        Turbolinks.visit "/some_request"
        @server.respond()

        assert.equal true, @pushStateStub.called, 'Should call pushState instead of redirecting.'

      it 'inserts script with a new src from new doc into head on navigation', ->
        @server.respondWith([200, { "Content-Type": "text/html" }, html_with_script_in_head])

        Turbolinks.visit "/some_request"
        @server.respond()

        assert.equal true, document.querySelectorAll('script[src="merp"]').length == 1, 'Should insert the script tag!'

      it 'does not reinsert script with existing src from new doc into head on navigation', ->
        @server.respondWith([200, { "Content-Type": "text/html" }, html_with_script_in_head])

        Turbolinks.visit "/some_request"
        @server.respond()

        Turbolinks.visit "/some_other_request"
        @server.respond()

        assert.equal true, document.querySelectorAll('script[src="merp"]').length == 1, 'Should insert the script tag once!'

      it 'inserts link tags with a new href from new doc into head on navigation', ->
        @server.respondWith([200, { "Content-Type": "text/html" }, html_with_link_in_head])

        Turbolinks.visit "/some_request"
        @server.respond()

        assert.equal 1, document.querySelectorAll('link[href="merp"]').length, 'Should add the new link tag!'

      it 'should remove link tags when navigating to a page with less of them', ->
        @server.respondWith([200, { "Content-Type": "text/html" }, html_with_link_in_head])
        Turbolinks.visit "/some_request"
        @server.respond()

        @server.respondWith([200, { "Content-Type": "text/html" }, html_one])
        Turbolinks.visit "/some_other_request"
        @server.respond()

        assert.equal 0, document.querySelectorAll('link[href="merp"]').length, 'Should remove the link!'


