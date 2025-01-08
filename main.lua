-- Variables globales (sin cambios)
local draggedCards = {}  -- Array para mantener todas las cartas siendo arrastradas
local draggedCard = nil
local dragStartX = 0
local dragStartY = 0
local dragSource = nil
local dragSourceIndex = nil
local deck = {}
local waste = {}
local tableaus = {{}, {}, {}, {}, {}, {}, {}}
local foundations = {{}, {}, {}, {}}
-- Agregar variables para las imágenes
local cardImages = {}  -- Table para almacenar todas las imágenes de cartas
local cardBack = nil   -- Imagen para el dorso de las cartas
local CARDS_PATH = "assets/cards/"
-- Al inicio del archivo, después de las otras variables globales
local bgShader = nil

-- Código del shader (después de las variables globales)
local shader_code = [[
    extern vec2 screen;
    extern number time;

    vec3 pal(in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d)
    {
        return a + b*cos(6.28318*(c*t+d));
    }

    vec4 effect(vec4 color, Image image, vec2 uvs, vec2 screen_coords)
    {
        vec2 uv = (screen_coords*2.0 - screen.xy)/screen.y;
        vec2 uv0 = uv;
        vec3 col = vec3(0.647,0.659,0.753);
        vec3 finalColor = vec3(1.0);
        
        uv0 = vec2(sin(2.0*time)/2.0);
        
        uv = fract(uv) - 0.5*exp(-length(uv0)*sin(time*2.0)/8.0);
        
        float d = 1.0;
        
        uv += vec2(time*0.02);
        uv = (fract(uv*4.0)-0.5);
        d = 0.6/abs(d);
        d *= length(uv) - 1.0;
        d = 0.1/d;
        d = d/0.1;
        d = abs(d);
        
        d *= length(uv)-0.5 * exp(-length(uv0));
        d = abs(d);
        
        d = 0.1/d;
        vec3 a = vec3(0.5);
        vec3 b = a;
        vec3 c = vec3(1.0);
        vec3 dd = vec3(-0.250,-0.125,0.123);
        finalColor = col*d*pal(time,a,b,c,dd);
        
        return vec4(finalColor, 1.0);
    }
]]

local bgShader = nil
local bgCanvas = nil  -- Para dibujar el fondo

local function getCardFileName(value, suit)
    -- Obtener el número del palo
    local suitNumber = "0"
    if suit == "hearts" then 
        suitNumber = "2"
    elseif suit == "diamonds" then 
        suitNumber = "4"
    elseif suit == "spades" then 
        suitNumber = "5"
    elseif suit == "clubs" then 
        suitNumber = "7"
    end
    
    -- Manejar cartas con cara (J, Q, K) de manera diferente
    if value == "J" or value == "Q" or value == "K" then
        return value .. suitNumber .. ".png"
    else
        -- Para As y cartas numerales, usar el formato con punto
        return value .. "." .. suitNumber .. ".png"
    end
end

local function checkAndFlipTableauCards()
    for _, tableau in ipairs(tableaus) do
        if #tableau > 0 then
            local lastCard = tableau[#tableau]
            if not lastCard.faceUp then
                lastCard.faceUp = true
            end
        end
    end
end

local function getTopVisibleCard(x, y)
    -- Primero revisar waste pile ya que siempre está encima
    if #waste > 0 then
        local topCard = waste[#waste]
        if x >= topCard.x and x <= topCard.x + 71 and
           y >= topCard.y and y <= topCard.y + 96 then
            return {
                card = topCard,
                source = 'waste',
                tableau = nil,
                index = #waste
            }
        end
    end
    
    -- Luego revisar los tableaus de adelante hacia atrás
    for i = 7, 1, -1 do  -- Invertimos el orden para revisar de derecha a izquierda
        local tableau = tableaus[i]
        for j = #tableau, 1, -1 do  -- Revisamos de arriba hacia abajo
            local card = tableau[j]
            if card.faceUp and 
               x >= card.x and x <= card.x + 71 and
               y >= card.y and y <= card.y + 96 then
                return {
                    card = card,
                    source = 'tableau',
                    tableau = i,
                    index = j
                }
            end
        end
    end
    
    return nil
end

local function getCardsAbove(tableau, startIndex)
    local cards = {}
    for i = startIndex, #tableau do
        table.insert(cards, tableau[i])
    end
    return cards
end

local function getCardColor(suit)
    if suit == 'hearts' or suit == 'diamonds' then
        return 'red'
    else
        return 'black'
    end
end

local function getCardValue(value)
    local values = {
        ['A'] = 1,
        ['2'] = 2,
        ['3'] = 3,
        ['4'] = 4,
        ['5'] = 5,
        ['6'] = 6,
        ['7'] = 7,
        ['8'] = 8,
        ['9'] = 9,
        ['10'] = 10,
        ['J'] = 11,
        ['Q'] = 12,
        ['K'] = 13
    }
    return values[value]
end

local function canPlaceOnCard(movingCard, targetCard)
    if not targetCard then return false end
    
    local movingValue = getCardValue(movingCard.value)
    local targetValue = getCardValue(targetCard.value)
    
    local movingColor = getCardColor(movingCard.suit)
    local targetColor = getCardColor(targetCard.suit)
    
    return movingValue == targetValue - 1 and movingColor ~= targetColor
end

local function canPlaceInFoundation(card, foundation)
    if #foundation == 0 then
        -- Solo se puede colocar un As en una foundation vacía
        return card.value == 'A'
    end
    
    local lastCard = foundation[#foundation]
    -- Debe ser del mismo palo y el siguiente valor
    return card.suit == lastCard.suit and 
           getCardValue(card.value) == getCardValue(lastCard.value) + 1
end

function table.contains(table, element)
    for _, value in pairs(table) do
        if value == element then
            return true
        end
    end
    return false
end

local function createDeck()
    local suits = {'hearts', 'diamonds', 'clubs', 'spades'}
    local values = {'A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'}
    
    -- Obtener dimensiones de una carta para usarlas en todo el juego
    local sampleImage = cardImages["Ahearts"]
    local cardWidth = sampleImage:getWidth()
    local cardHeight = sampleImage:getHeight()
    
    for _, suit in ipairs(suits) do
        for _, value in ipairs(values) do
            local card = {
                suit = suit,
                value = value,
                faceUp = false,
                x = 50,
                y = 50,
                width = cardWidth,
                height = cardHeight
            }
            table.insert(deck, card)
        end
    end
end

local function shuffleDeck()
    for i = #deck, 2, -1 do
        local j = love.math.random(i)
        deck[i], deck[j] = deck[j], deck[i]
    end
end

local function dealCards()
    -- Repartir cartas a los tableaus
    for i = 1, 7 do
        for j = 1, i do
            local card = table.remove(deck)
            card.faceUp = (j == i)  -- Solo la última carta boca arriba
            card.x = 100 + (i-1) * 100
            card.y = 150 + (j-1) * 30
            table.insert(tableaus[i], card)
        end
    end
end

local function drawCard(card)
    if card.faceUp then
        -- Dibujar carta boca arriba usando la imagen correspondiente
        local imageKey = card.value .. card.suit
        local cardImage = cardImages[imageKey]
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(cardImage, card.x, card.y)
    else
        -- Dibujar carta boca abajo usando la imagen del dorso
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(cardBack, card.x, card.y)
    end
end
-- Función auxiliar para el manejo de errores
function love.errhand(msg)
    print("ERROR EN EL JUEGO:", msg)
    print(debug.traceback())
    bgShader = nil -- Desactivar el shader si hay un error
    return false -- Permite que el juego continúe
end
function love.load()
 -- Configuración de la ventana
    love.window.setMode(800, 600)
    
    bgShader = love.graphics.newShader(shader_code)
    -- Crear un canvas para el fondo
    bgCanvas = love.graphics.newCanvas(800, 600)
    
    -- Cargar el resto de los assets incluso si el shader falla
    -- Cargar imagen del dorso de la carta
    cardBack = love.graphics.newImage(CARDS_PATH .. "BACK.png")
    
    -- Cargar todas las imágenes de las cartas
    local suits = {'hearts', 'diamonds', 'clubs', 'spades'}
    local values = {'A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'}
    
    for _, suit in ipairs(suits) do
        for _, value in ipairs(values) do
            local fileName = getCardFileName(value, suit)
            local imageKey = value .. suit
            local imagePath = CARDS_PATH .. fileName
            print("Loading: " .. imagePath)
            cardImages[imageKey] = love.graphics.newImage(imagePath)
        end
    end
    
    -- Inicializar el juego
    createDeck()
    shuffleDeck()
    dealCards()
end

function love.update(dt)
    -- Actualizar posición de todas las cartas arrastradas
    
    if #draggedCards > 0 then
        local baseX = love.mouse.getX() - dragStartX
        local baseY = love.mouse.getY() - dragStartY
        local offset = 0
        for i, card in ipairs(draggedCards) do
            card.x = baseX
            card.y = baseY + offset
            offset = offset + 30  -- Espaciado vertical entre cartas
        end
    end
end

function love.mousepressed(x, y, button)
    if button == 1 then
        -- Revisar click en el mazo o área de reinicio
        if x >= 50 and x <= 121 and y >= 50 and y <= 146 then
            if #deck > 0 then
                local card = table.remove(deck)
                card.faceUp = true
                card.x = 200
                card.y = 50
                table.insert(waste, card)
                return
            elseif #deck == 0 and #waste > 0 then
                for i = #waste, 1, -1 do
                    local card = table.remove(waste)
                    card.faceUp = false
                    table.insert(deck, card)
                end
                return
            end
        end
        
        -- Obtener la carta más visible en la posición del click
        local clickedCard = getTopVisibleCard(x, y)
        if clickedCard then
            if clickedCard.source == 'waste' then
                -- Para el waste pile, solo movemos una carta
                draggedCards = {clickedCard.card}
                -- Guardar posición original
                clickedCard.card.originalX = clickedCard.card.x
                clickedCard.card.originalY = clickedCard.card.y
                dragStartX = x - clickedCard.card.x
                dragStartY = y - clickedCard.card.y
                dragSource = 'waste'
                dragSourceIndex = clickedCard.index
            else
                -- Para tableau, obtenemos la carta clickeada y todas las que están encima
                draggedCards = getCardsAbove(tableaus[clickedCard.tableau], clickedCard.index)
                dragStartX = x - clickedCard.card.x
                dragStartY = y - clickedCard.card.y
                dragSource = 'tableau'
                dragSourceIndex = clickedCard.index
                dragSourceTableau = clickedCard.tableau
                -- Guardar posición original de todas las cartas
                for _, dragCard in ipairs(draggedCards) do
                    dragCard.originalX = dragCard.x
                    dragCard.originalY = dragCard.y
                end
            end
        end
    end
end

function love.mousereleased(x, y, button)
    if button == 1 and #draggedCards > 0 then
        local validMove = false
        for _, card in ipairs(draggedCards) do
            if not card.originalX or not card.originalY then
                card.originalX = card.x
                card.originalY = card.y
            end
        end
        
        -- Solo permitir mover una carta a la vez a las foundations
        if #draggedCards == 1 then
            -- Verificar foundations
            for i = 1, 4 do
                local foundationX = 400 + (i-1) * 100
                if x >= foundationX and x <= foundationX + 71 and
                   y >= 50 and y <= 146 then
                    local targetFoundation = foundations[i]
                    local card = draggedCards[1]
                    
                    -- Verificar que la foundation corresponde al palo correcto
                    local correctSuit = false
                    if i == 1 and card.suit == 'hearts' then correctSuit = true
                    elseif i == 2 and card.suit == 'diamonds' then correctSuit = true
                    elseif i == 3 and card.suit == 'clubs' then correctSuit = true
                    elseif i == 4 and card.suit == 'spades' then correctSuit = true
                    end
                    
                    if correctSuit and canPlaceInFoundation(card, targetFoundation) then
                        validMove = true
                        -- Remover la carta de su origen
                        if dragSource == 'waste' then
                            table.remove(waste, dragSourceIndex)
                        else
                            table.remove(tableaus[dragSourceTableau], dragSourceIndex)
                        end
                        
                        -- Colocar la carta en la foundation
                        card.x = foundationX
                        card.y = 50
                        table.insert(targetFoundation, card)
                    end
                    break
                end
            end
        end
        
        -- Si no fue un movimiento válido a una foundation, intentar mover a un tableau
        if not validMove then
            -- Verificar cada tableau (código existente)
            for i, tableau in ipairs(tableaus) do
                local tableauX = 100 + (i-1) * 100
                
                if x >= tableauX and x <= tableauX + 71 then
                    local canPlace = false
                    local baseY = 150
                    
                    if #tableau == 0 then
                        canPlace = draggedCards[1].value == 'K'
                        baseY = 150
                    else
                        local lastCard = tableau[#tableau]
                        canPlace = canPlaceOnCard(draggedCards[1], lastCard)
                        baseY = lastCard.y + 30
                    end
                    
                    if canPlace then
                        validMove = true
                        if dragSource == 'waste' then
                            table.remove(waste, dragSourceIndex)
                        else
                            for j = 1, #draggedCards do
                                table.remove(tableaus[dragSourceTableau], dragSourceIndex)
                            end
                        end
                        
                        for j, card in ipairs(draggedCards) do
                            card.x = tableauX
                            card.y = baseY + (j-1) * 30
                            table.insert(tableaus[i], card)
                        end
                    end
                    break
                end
            end
        end
        
        -- Si no fue un movimiento válido, regresar las cartas
        if not validMove then
            for _, card in ipairs(draggedCards) do
                card.x = card.originalX
                card.y = card.originalY
            end
        else
            checkAndFlipTableauCards()
        end
        
        -- Limpiar variables de drag
        draggedCards = {}
        dragSource = nil
        dragSourceIndex = nil
        dragSourceTableau = nil
    end
end

function love.draw()
    -- Dibujar fondo con shader
 if bgShader then
        love.graphics.setShader(bgShader)
        
        -- Enviar variables uniformes al shader
        bgShader:send("screen", {love.graphics.getWidth(), love.graphics.getHeight()})
        bgShader:send("time", love.timer.getTime())
        
        -- Dibujar un rectángulo que cubra toda la pantalla
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle('fill', 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
        love.graphics.setShader()
    else
        -- Fondo de respaldo
        love.graphics.setColor(0.2, 0.5, 0.3)
        love.graphics.rectangle('fill', 0, 0, 800, 600)
    end
    
    -- Restaurar color para el resto del dibujo
    love.graphics.setColor(1, 1, 1)
    
    -- Dibujar mazo o área de reinicio
    if #deck > 0 then
        -- Usar la imagen del dorso para el deck
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(cardBack, 50, 50)
    else
        -- Dibujar área de reinicio cuando el deck está vacío
        love.graphics.setColor(0.4, 0.4, 0.4)
        love.graphics.rectangle('line', 50, 50, 71, 96)
        love.graphics.circle('line', 85, 98, 15)
        love.graphics.line(85, 83, 85, 93)
        love.graphics.line(85, 93, 90, 88)
        love.graphics.line(85, 93, 80, 88)
    end
    love.graphics.setColor(1, 1, 1)
    
    -- Dibujar foundations con etiquetas de palo
    for i, foundation in ipairs(foundations) do
        local foundationX = 400 + (i-1) * 100
        love.graphics.setColor(1, 1, 1)
        love.graphics.rectangle('line', foundationX, 50, 71, 96)
        
        -- Dibujar etiqueta del palo
        local suit = ''
        if i == 1 then suit = 'H'
        elseif i == 2 then suit = 'D'
        elseif i == 3 then suit = 'C'
        elseif i == 4 then suit = 'S'
        end
        
        if #foundation == 0 then
            love.graphics.setColor(0.5, 0.5, 0.5)
            love.graphics.print(suit, foundationX + 30, 85)
        else
            drawCard(foundation[#foundation])
        end
    end
    
    -- Dibujar waste pile
    for _, card in ipairs(waste) do
        if not table.contains(draggedCards, card) then
            drawCard(card)
        end
    end
    
    -- Dibujar tableaus
    for _, tableau in ipairs(tableaus) do
        for _, card in ipairs(tableau) do
            if not table.contains(draggedCards, card) then
                drawCard(card)
            end
        end
    end
    
    -- Dibujar cartas arrastradas al final
    for _, card in ipairs(draggedCards) do
        drawCard(card)
    end
end
