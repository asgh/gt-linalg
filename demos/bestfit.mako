## -*- coffee -*-

<%inherit file="base2.mako"/>

<%block name="title">Function of Best Fit</%block>

<%block name="inline_style">
  #eqn-here {
    color: red
  }
  #sumsq-here {
    color: #cc00ff
  }
</%block>

##

range = urlParams.get 'range', 'float', 10

# urlParams.func has to be of the form A*blah1(x)+B*blah2(x)-C*blah3(x)+D
# (spaces are not allowed)
# You may use '$' in place of '%2d' in the URL
funcStr = urlParams.func ? 'C*x+D'
funcStr = funcStr.replace /\$/g, '+'
func = exprEval.Parser.parse funcStr
# x and y are function variables; the rest are parameters
params = []
zeroParams = {}
vars = []
for letter in func.variables().sort()
    if letter in ['x', 'y']
        vars.push letter
    else
        params.push letter
        zeroParams[letter] = 0
size = vars.length + 1
numParams = params.length

# unit coordinate vectors in the parameters
units = []
for i in [0...numParams]
    obj = {}
    for param in params
        obj[param] = 0
    obj[params[i]] = 1
    units.push obj

# Target vectors
targets = []
i = 1
while urlParams["v#{i}"]?
    targets.push urlParams.get "v#{i}", 'float[]'
    i++
numTargets = targets.length

# Set up the linear equations
# The matrix has numParams columns, each with numTargets rows
matrix = ((0 for [0...numTargets]) for [0...numParams])
bvec = (0 for [0...numTargets])
xhat = (0 for [0...numParams])
bestfit = (x) -> 0
bestFitStr = ''

dot = (v1, v2) ->
    ret = 0
    for i in [0...v1.length]
        ret += v1[i] * v2[i]
    ret

updateCaption = () ->

solve = () ->
    # First have to figure out the coefficients of matrix and bvec
    for eqno in [0...numTargets]
        target = targets[eqno]
        toEval = {}
        for letter, i in vars
            toEval[letter] = target[i]
        linear = func.simplify toEval
        # linear is now an (affine linear) function of the parameters only
        # First get the constant term
        constant = linear.evaluate zeroParams
        # Now get the linear terms
        for i in [0...numParams]
            matrix[i][eqno] = linear.evaluate(units[i]) - constant
        # The last coordinate of the target is the right-hand side of the equation
        bvec[eqno] = target[size-1] - constant
    # Now least-squares solve Ax=b
    ATA = ((dot(matrix[i], matrix[j]) for i in [0...numParams]) for j in [0...numParams])
    ATb = (dot(matrix[i], bvec) for i in [0...numParams])
    solver = rowReduce(ATA)[3]
    solver ATb, xhat
    # Substitute the parameters to get the best-fit function
    toEval = {}
    for letter, i in params
        toEval[letter] = xhat[i]
    bestfit = func.simplify(toEval).toJSFunction(vars.join ',')
    makeString()
    updateCaption()

makeString = () ->
    # Make a TeX string out of the function
    bestFitStr = funcStr
    for letter, i in params
        val = xhat[i]
        if val >= 0
            valAlone = val.toFixed 2
            valPlus  = "+#{valAlone}"
            valMinus = "-#{valAlone}"
        if val < 0
            val = -val
            valAlone = val.toFixed 2
            valPlus  = "-#{valAlone}"
            valMinus = "+#{valAlone}"
            valAlone = "-#{valAlone}"
        bestFitStr = bestFitStr.replace("+#{letter}*", valPlus  + '\\,')
        bestFitStr = bestFitStr.replace("+#{letter}",  valPlus)
        bestFitStr = bestFitStr.replace("-#{letter}*", valMinus + '\\,')
        bestFitStr = bestFitStr.replace("-#{letter}",  valMinus)
        bestFitStr = bestFitStr.replace( "#{letter}*", valAlone + '\\,')
        bestFitStr = bestFitStr.replace( "#{letter}",  valAlone)
        # This should work for most TeX functions
        for op in func.unaryOps
            if op.match /^[a-zA-Z]+$/
                bestFitStr = bestFitStr.replace(op, "\\#{op}")

solve()


window.demo = new (if size == 2 then Demo2D else Demo) {}, () ->
    window.mathbox = @mathbox

    view = @view
        axes:  true
        grid:  true
        range: [[-range,range],[-range,range],[-range,range]].slice(0, size)

    ##################################################
    # (Unlabeled) points
    @labeledPoints view,
        name:      'targets'
        points:    targets
        colors:    ([0, .5, .8, 1] for [0...numTargets])
        live:      true
        pointOpts: zIndex: 2

    ##################################################
    # Graph the best-fit function
    if size == 2
        view
            .interval
                channels: 2
                range:    [-range, range]
                width:    100
                expr: (emit, x) ->
                    emit(x, bestfit x)
            .line
                color:  "red"
                width:  4
                zIndex: 1
    if size == 3
        clipCube = @clipCube view,
            draw:     true
            color:    new THREE.Color .75, .75, .75
        clipCube.clipped
            .area
                channels: 3
                rangeX:   [-range, range]
                rangeY:   [-range, range]
                width:    100
                height:   100
                expr: (emit, x, y) ->
                    emit(x, y, bestfit(x, y))
            .surface
                color:   0xaa0000
                opacity: .5
                zIndex:  1
                fill:    true
                lineX:   false
                lineY:   false
            .resample
                shader:  null
                size:    'relative'
                width:   1/10
                height:  1/10
            .surface
                color:   0xbb0000
                opacity: .6
                zIndex:  1
                zBias:   2
                fill:    false
                lineX:   true
                lineY:   true

    ##################################################
    # Draw error lines
    view
        .array
            channels: size
            width:    2
            items:    numTargets
            expr: (emit, end) ->
                for i in [0...numTargets]
                    x = targets[i][0]
                    y = targets[i][1]
                    if size == 2
                        if end
                            emit(x, bestfit x)
                        else
                            emit(x, y)
                    if size == 3
                        z = targets[i][2]
                        if end
                            emit(x, y, bestfit(x, y))
                        else
                            emit(x, y, z)
        .line
            color:  0xaa00dd
            width:  2
            zIndex: 3

    ##################################################
    # Dragging and snapping
    @draggable view,
        points:   targets
        postDrag: solve

    ##################################################
    # Caption
    str  = '<p>Best-fit equation: <span id="eqn-here"></span></p>'
    str += '<p>Quantity minimized: <span id="sumsq-here"></span></p>'
    @caption str
    bestFitElt = document.getElementById 'eqn-here'
    minimElt   = document.getElementById 'sumsq-here'
    varsStr    = vars.join ','

    updateCaption = () =>
        katex.render "\\quad f(#{varsStr}) = #{bestFitStr}", bestFitElt
        minimized = []
        quantity = 0
        for target in targets
            if size == 2
                diff = target[1] - bestfit(target[0])
            if size == 3
                diff = target[2] - bestfit(target[0], target[1])
            minimized.push "#{diff.toFixed 2}^2"
            quantity += diff*diff
        str = '\\quad' + quantity.toFixed(2) + '=' + minimized.join('+')
        katex.render str, minimElt

    updateCaption()