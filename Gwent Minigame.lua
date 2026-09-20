local W, H = 480, 800

-- Game State Variables
local playerHand, aiHand = {}, {}
local playerRows, aiRows
local playerGems, aiGems
local playerPassed, aiPassed
local playerLeader, aiLeader
local playerLeaderUsed, aiLeaderUsed
local weather = { frost = false, fog = false, rain = false }

local state, turnOwner, selectedCardIdx
local lastMsg, scoreP, scoreAI
local currentView = "cards"

----------------------------------------------------
-- DRAWING HELPERS (SIZE 4 TEXT)
----------------------------------------------------
local function drawThickRect(x, y, w, h, t, c)
  for i = 0, t - 1 do
    drawRect(x + i, y + i, w - 2 * i, h - 2 * i, c)
  end
end

local function drawTextCentered(str, x, y, w, h, col, size)
  if not str or str == "" then return end
  size = size or 4
  setTextSize(size)
  setTextColor(col or BLACK)
  local tw = textWidth(str)
  local cx = x + math.floor((w - tw) / 2)
  local cy = y + math.floor(h / 2) - (size * 4)
  setCursor(cx, cy)
  text(str)
end

----------------------------------------------------
-- FULL GWENT CARD DATABASE
----------------------------------------------------
local LEADERS = {
  { name = "FOLTEST", desc = "CLEAR WX" },
  { name = "EREDIN", desc = "+1 GEM" },
  { name = "EMHYR", desc = "CANCEL WX" },
  { name = "FRANCESCA", desc = "DOUBLE RANGED" }
}

local FULL_CARD_POOL = {
  -- HERO UNITS
  { type = "unit", isHero = true, row = "close", rowName = "MELEE", power = 15, name = "GERALT 15" },
  { type = "unit", isHero = true, row = "close", rowName = "MELEE", power = 15, name = "CIRI 15" },
  { type = "unit", isHero = true, row = "ranged", rowName = "RANGED", power = 10, name = "YENNEFER 10" },
  { type = "unit", isHero = true, row = "ranged", rowName = "RANGED", power = 10, name = "TRISS 10" },
  { type = "unit", isHero = true, row = "siege", rowName = "SIEGE", power = 10, name = "VERNON ROCHE 10" },
  { type = "unit", isHero = true, row = "close", rowName = "MELEE", power = 10, name = "LETHO 10" },
  { type = "unit", isHero = true, row = "ranged", rowName = "RANGED", power = 10, name = "IORVETH 10" },
  { type = "unit", isHero = true, row = "close", rowName = "MELEE", power = 10, name = "IMLERITH 10" },

  -- REGULAR & SPECIAL UNITS
  { type = "unit", isHero = false, row = "close", rowName = "MELEE", power = 7, name = "VESEMIR 7" },
  { type = "unit", isHero = false, row = "close", rowName = "MELEE", power = 6, name = "ZOLTAN 6" },
  { type = "unit", isHero = false, row = "close", rowName = "MELEE", power = 5, name = "DANDELION 5" },
  { type = "unit", isHero = false, row = "ranged", rowName = "RANGED", power = 6, name = "MILVA 6" },
  { type = "unit", isHero = false, row = "siege", rowName = "SIEGE", power = 8, name = "TREBUCHET 8" },
  { type = "unit", isHero = false, row = "siege", rowName = "SIEGE", power = 6, name = "CATAPULT 6" },
  { type = "unit", isHero = false, row = "close", rowName = "MELEE", power = 4, name = "FIEND 4" },
  { type = "unit", isHero = false, row = "ranged", rowName = "RANGED", power = 5, name = "ARACHAS 5" },
  { type = "unit", isHero = false, row = "close", rowName = "MELEE", power = 2, ability = "spy", name = "SPY MELEE 2" },
  { type = "unit", isHero = false, row = "ranged", rowName = "RANGED", power = 4, ability = "spy", name = "SPY RANGED 4" },
  { type = "unit", isHero = false, row = "ranged", rowName = "RANGED", power = 4, ability = "bond", name = "BOND RANGED 4" },
  { type = "unit", isHero = false, row = "close", rowName = "MELEE", power = 5, ability = "bond", name = "BOND MELEE 5" },

  -- SPECIAL WEATHER CARDS
  { type = "special", specialType = "frost", name = "BITING FROST" },
  { type = "special", specialType = "fog", name = "IMPENETRABLE FOG" },
  { type = "special", specialType = "rain", name = "TORRENTIAL RAIN" },
  { type = "special", specialType = "clear", name = "CLEAR WEATHER" },
  { type = "special", specialType = "scorch", name = "SCORCH CARD" }
}

----------------------------------------------------
-- DECK & GAME GENERATION
----------------------------------------------------
local function getRandomLeader()
  return LEADERS[random(1, #LEADERS)]
end

local function generateFullHand()
  local hand = {}
  local poolCopy = {}
  for _, c in ipairs(FULL_CARD_POOL) do
    table.insert(poolCopy, c)
  end

  for i = 1, 10 do
    if #poolCopy > 0 then
      local idx = random(1, #poolCopy)
      table.insert(hand, table.remove(poolCopy, idx))
    end
  end

  return hand
end

----------------------------------------------------
-- SCORING LOGIC
----------------------------------------------------
local function getEffectivePower(card, rowType)
  if card.type ~= "unit" then return 0 end
  if card.isHero then return card.power end

  if (rowType == "close" and weather.frost) or
     (rowType == "ranged" and weather.fog) or
     (rowType == "siege" and weather.rain) then
    return 1
  end
  return card.power
end

local function getRowScore(rowCards, rowType)
  local sum = 0
  for _, card in ipairs(rowCards) do
    sum = sum + getEffectivePower(card, rowType)
  end
  return sum
end

local function getTotalSideScore(rows)
  return getRowScore(rows.close, "close") +
         getRowScore(rows.ranged, "ranged") +
         getRowScore(rows.siege, "siege")
end

----------------------------------------------------
-- GAME CONTROL
----------------------------------------------------
local function resetRound()
  playerRows = { close = {}, ranged = {}, siege = {} }
  aiRows = { close = {}, ranged = {}, siege = {} }
  playerPassed = false
  aiPassed = false
  weather = { frost = false, fog = false, rain = false }
end

local function resetGame()
  playerHand = generateFullHand()
  aiHand = generateFullHand()

  playerLeader = getRandomLeader()
  aiLeader = getRandomLeader()
  playerLeaderUsed = false
  aiLeaderUsed = false

  playerGems = 2
  aiGems = 2
  selectedCardIdx = 1
  lastMsg = "GAME STARTED"
  state = "play"
  turnOwner = "player"
  currentView = "cards"
  resetRound()
end

function init(w, h)
  W = w
  H = h
  resetGame()
  state = "menu"
end

local function checkRoundEnd()
  if playerPassed and aiPassed then
    local pTot = getTotalSideScore(playerRows)
    local aiTot = getTotalSideScore(aiRows)

    if pTot > aiTot then
      aiGems = aiGems - 1
      lastMsg = "YOU WON ROUND"
    elseif aiTot > pTot then
      playerGems = playerGems - 1
      lastMsg = "AI WON ROUND"
    else
      playerGems = playerGems - 1
      aiGems = aiGems - 1
      lastMsg = "ROUND TIED"
    end

    if playerGems <= 0 or aiGems <= 0 then
      state = "over"
    else
      resetRound()
      turnOwner = "player"
    end
    return true
  end
  return false
end

local function applyScorch()
  local maxPwr = 0
  for _, rName in ipairs({"close", "ranged", "siege"}) do
    for _, c in ipairs(playerRows[rName]) do
      if not c.isHero and c.power > maxPwr then maxPwr = c.power end
    end
    for _, c in ipairs(aiRows[rName]) do
      if not c.isHero and c.power > maxPwr then maxPwr = c.power end
    end
  end

  if maxPwr > 0 then
    for _, rName in ipairs({"close", "ranged", "siege"}) do
      for i = #playerRows[rName], 1, -1 do
        local c = playerRows[rName][i]
        if not c.isHero and c.power == maxPwr then table.remove(playerRows[rName], i) end
      end
      for i = #aiRows[rName], 1, -1 do
        local c = aiRows[rName][i]
        if not c.isHero and c.power == maxPwr then table.remove(aiRows[rName], i) end
      end
    end
  end
end

local function playCard(hand, rows, cardIdx, targetRows)
  local card = table.remove(hand, cardIdx)
  if card.type == "unit" then
    if card.ability == "spy" and targetRows then
      table.insert(targetRows.close, card)
    else
      table.insert(rows[card.row], card)
    end
  elseif card.type == "special" then
    if card.specialType == "clear" then
      weather.frost, weather.fog, weather.rain = false, false, false
    elseif card.specialType == "frost" then
      weather.frost = true
    elseif card.specialType == "fog" then
      weather.fog = true
    elseif card.specialType == "rain" then
      weather.rain = true
    elseif card.specialType == "scorch" then
      applyScorch()
    end
  end
  return card
end

local function switchTurn()
  if checkRoundEnd() then return end

  if turnOwner == "player" then
    if not aiPassed then
      turnOwner = "ai"
      state = "ai_think"
    end
  else
    if not playerPassed then
      turnOwner = "player"
      state = "play"
    end
  end
end

local function aiPlayTurn()
  local pTotBefore = getTotalSideScore(playerRows)
  local aiTotBefore = getTotalSideScore(aiRows)

  if playerPassed and aiTotBefore > pTotBefore then
    aiPassed = true
    lastMsg = "AI PASSED"
    switchTurn()
    return
  end

  if #aiHand == 0 then
    aiPassed = true
    lastMsg = "AI PASSED"
    switchTurn()
    return
  end

  local played = playCard(aiHand, aiRows, 1, playerRows)
  lastMsg = "AI PLAYED: " .. played.name
  switchTurn()
end

local function activateLeader(isPlayer)
  if isPlayer and not playerLeaderUsed then
    playerLeaderUsed = true
    if playerLeader.name == "FOLTEST" or playerLeader.name == "EMHYR" then
      weather.frost, weather.fog, weather.rain = false, false, false
      lastMsg = "LEADER: CLEARED"
    else
      playerGems = math.min(2, playerGems + 1)
      lastMsg = "LEADER: +1 GEM"
    end
    switchTurn()
  end
end

----------------------------------------------------
-- MAIN DRAW METHOD (SIZE 4 RENDERING)
----------------------------------------------------
function draw()
  fillScreen(WHITE)
  drawHeader("GWENT")

  scoreP = getTotalSideScore(playerRows)
  scoreAI = getTotalSideScore(aiRows)

  if state == "ai_think" then
    aiPlayTurn()
  end

  -- MENU STATE
  if state == "menu" then
    drawTextCentered("GWENT", 0, 70, W, 80, BLACK, 4)
    drawThickRect(15, 160, 450, 480, 5, BLACK)
    drawTextCentered("L/R: SCROLL", 15, 260, 450, 60, BLACK, 4)
    drawTextCentered("OK: PLAY", 15, 340, 450, 60, BLACK, 4)
    drawTextCentered("BACK: TOGGLE", 15, 420, 450, 60, BLACK, 4)
    drawTextCentered("UP: LEADER", 15, 500, 450, 60, BLACK, 4)
    drawTextCentered("DOWN: PASS", 15, 560, 450, 60, BLACK, 4)

    fillRect(25, 660, 430, 80, BLACK)
    drawTextCentered("PRESS OK", 25, 660, 430, 80, WHITE, 4)
    drawFooter("Back: Exit", "OK: Start")
    return
  end

  -- SCREEN VIEW 1: BOARD OVERVIEW SCREEN (SIZE 4)
  if currentView == "board" then
    drawThickRect(10, 40, 460, 680, 5, BLACK)
    
    -- Line 1: AI Score & Gems
    drawTextCentered("AI: " .. scoreAI .. " | GEM:" .. aiGems, 10, 50, 460, 80, BLACK, 4)
    fillRect(25, 140, 430, 6, BLACK)

    -- Line 2: AI Board Summary
    local aiM = getRowScore(aiRows.close, "close")
    local aiR = getRowScore(aiRows.ranged, "ranged")
    local aiS = getRowScore(aiRows.siege, "siege")
    drawTextCentered("AI M:" .. aiM .. " R:" .. aiR .. " S:" .. aiS, 10, 155, 460, 80, BLACK, 4)
    fillRect(25, 245, 430, 6, BLACK)

    -- Line 3: Active Weather
    local wStr = "WX: " .. (weather.frost and "FROST " or "") .. (weather.fog and "FOG " or "") .. (weather.rain and "RAIN" or "")
    if not (weather.frost or weather.fog or weather.rain) then wStr = "WX: CLEAR" end
    drawTextCentered(wStr, 10, 260, 460, 80, BLACK, 4)
    fillRect(25, 350, 430, 6, BLACK)

    -- Line 4: Player Board Summary
    local pM = getRowScore(playerRows.close, "close")
    local pR = getRowScore(playerRows.ranged, "ranged")
    local pS = getRowScore(playerRows.siege, "siege")
    drawTextCentered("YOU M:" .. pM .. " R:" .. pR .. " S:" .. pS, 10, 365, 460, 80, BLACK, 4)
    fillRect(25, 455, 430, 6, BLACK)

    -- Line 5: Player Score & Gems
    drawTextCentered("YOU: " .. scoreP .. " | GEM:" .. playerGems, 10, 470, 460, 80, BLACK, 4)
    fillRect(25, 560, 430, 6, BLACK)

    -- Line 6: Last Action Log
    drawTextCentered(lastMsg, 10, 575, 460, 120, BLACK, 4)

    drawFooter("Back: Cards", "DOWN: Pass")
    return
  end

  -- SCREEN VIEW 2: CARD CAROUSEL SCREEN (SIZE 4)
  drawThickRect(10, 40, 460, 680, 5, BLACK)

  -- Line 1: Leader Status Header
  local lStr = "LDR: " .. playerLeader.name .. (playerLeaderUsed and " [USED]" or " [UP]")
  drawTextCentered(lStr, 10, 50, 460, 80, BLACK, 4)
  fillRect(25, 140, 430, 6, BLACK)

  if #playerHand > 0 and selectedCardIdx <= #playerHand then
    local selCard = playerHand[selectedCardIdx]

    -- Line 2: Card Position Indicator
    drawTextCentered("< " .. selectedCardIdx .. " / " .. #playerHand .. " >", 10, 155, 460, 80, BLACK, 4)
    
    -- Line 3: Giant Card Name Display Block
    fillRect(25, 245, 430, 120, BLACK)
    drawTextCentered(selCard.name, 25, 245, 430, 120, WHITE, 4)

    -- Line 4: Card Target Row
    local rStr = selCard.type == "unit" and ("ROW: " .. selCard.rowName) or "TYPE: SPECIAL"
    drawTextCentered(rStr, 10, 380, 460, 80, BLACK, 4)

    -- Line 5: Card Base Power / Effect
    local pStr = selCard.type == "unit" and ("POWER: " .. selCard.power) or ("EFFECT: " .. (selCard.specialType or "NONE"))
    drawTextCentered(pStr, 10, 475, 460, 80, BLACK, 4)

    -- Line 6: Main Play Action Prompt Block
    fillRect(25, 570, 430, 130, BLACK)
    drawTextCentered("PRESS OK", 25, 570, 430, 130, WHITE, 4)
  else
    drawTextCentered("EMPTY HAND", 10, 260, 460, 100, BLACK, 4)
    drawTextCentered("DOWN: PASS", 10, 390, 460, 100, BLACK, 4)
  end

  -- GAME OVER OVERLAY
  if state == "over" then
    fillRect(15, 150, 450, 480, WHITE)
    drawThickRect(15, 150, 450, 480, 5, BLACK)

    fillRect(30, 180, 420, 120, BLACK)
    if playerGems > aiGems then
      drawTextCentered("VICTORY!", 30, 180, 420, 120, WHITE, 4)
    elseif aiGems > playerGems then
      drawTextCentered("DEFEAT!", 30, 180, 420, 120, WHITE, 4)
    else
      drawTextCentered("DRAW!", 30, 180, 420, 120, WHITE, 4)
    end

    drawTextCentered("YOU GEMS: " .. playerGems, 15, 320, 450, 80, BLACK, 4)
    drawTextCentered("AI GEMS: " .. aiGems, 15, 410, 450, 80, BLACK, 4)

    fillRect(30, 510, 420, 90, BLACK)
    drawTextCentered("RESTART [OK]", 30, 510, 420, 90, WHITE, 4)
  end

  drawFooter("Back: Board", "OK: Play")
end

----------------------------------------------------
-- BUTTON INPUT HANDLER
----------------------------------------------------
function onButton(btn)
  if (state == "menu" or state == "over") and btn == "back" then
    return false
  end

  if (state == "play" or state == "ai_think") and btn == "back" then
    if currentView == "cards" then
      currentView = "board"
    else
      currentView = "cards"
    end
    return true
  end

  if state == "menu" or state == "over" then
    if btn == "center" then
      resetGame()
    end
    return true
  end

  if state == "play" then
    if btn == "up" then
      activateLeader(true)
      return true
    end

    if playerPassed then return true end

    if btn == "left" then
      selectedCardIdx = selectedCardIdx - 1
      if selectedCardIdx < 1 then selectedCardIdx = math.max(1, #playerHand) end
    elseif btn == "right" then
      selectedCardIdx = selectedCardIdx + 1
      if selectedCardIdx > #playerHand then selectedCardIdx = 1 end
    elseif btn == "down" then
      playerPassed = true
      lastMsg = "YOU PASSED"
      switchTurn()
    elseif btn == "center" then
      if #playerHand > 0 and selectedCardIdx <= #playerHand then
        local played = playCard(playerHand, playerRows, selectedCardIdx, aiRows)
        lastMsg = "PLAYED: " .. played.name
        if selectedCardIdx > #playerHand then
          selectedCardIdx = math.max(1, #playerHand)
        end
        switchTurn()
      end
    end
    return true
  end

  return true
end