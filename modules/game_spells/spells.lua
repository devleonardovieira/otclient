-- Módulo cliente para cast de spells com pré-cast visual
-- API principal: GameSpells.castSpell(words, opts?)
-- opts = { parameter = string, effectId = number, durationMs = number }

GameSpells = {}

local DEFAULT_PRECAST_DURATION = 500 -- ms

-- Mapeamentos básicos de pré-cast por grupo primário (Spells.getPrimaryGroup)
-- 1=Attack, 2=Healing, 3=Support, ... ver modules/gamelib/spells.lua
local GroupPrecastEffect = {
  [1] = 8,   -- Attack → 'Ki' aura externa (id 8)
  [2] = 3,   -- Healing → 'Angel Light' (id 3)
  [3] = 7,   -- Support → 'Pentagram Aura' (id 7)
}

-- Mapeamento opcional por palavras (override por spell específico)
-- Adicione aqui para ajustar efeitos por spell individual.
local WordsPrecastEffect = {
  ['exura'] = 3,                 -- Light Healing
  ['exura gran'] = 3,            -- Intense Healing
  ['exura vita'] = 3,            -- Ultimate Healing
  ['exevo flam hur'] = 8,        -- Fire Wave
  ['exevo gran flam hur'] = 8,   -- Great Fire Wave
  ['exevo vis hur'] = 8,         -- Energy Wave
}

local function resolvePrecastEffectId(words)
  if type(words) ~= 'string' or words == '' then return nil end
  local spellData = Spells.getSpellDataByWords(words)
  if not spellData then
    -- Tenta com formatação para casos com parâmetro e aspas
    local formatted = Spells.getSpellFormatedName(words)
    spellData = Spells.getSpellDataByWords(formatted)
  end
  if not spellData then
    return WordsPrecastEffect[words] -- fallback direto por palavras, se existir
  end
  -- Override específico por palavras tem prioridade
  if WordsPrecastEffect[spellData.words] then
    return WordsPrecastEffect[spellData.words]
  end
  -- Caso contrário, por grupo primário
  local primaryGroup = Spells.getPrimaryGroup(spellData)
  return GroupPrecastEffect[primaryGroup]
end

local function attachPrecast(effectId, durationMs)
  if not effectId then return end
  local player = g_game.getLocalPlayer()
  if not player then return end
  local base = g_attachedEffects.getById(effectId)
  if not base then return end
  local e = base:clone()
  -- Força duração curta e loop único para efeito de pré-cast
  e:setDuration(durationMs or DEFAULT_PRECAST_DURATION)
  e:setLoop(1)
  player:attachEffect(e)
end

-- Normaliza string de fala, aplicando aspas quando houver parâmetro
local function buildTalkText(words, parameter)
  if parameter and parameter ~= '' then
    return (words or '') .. ' "' .. parameter .. '"'
  end
  return words
end

function GameSpells.init()
  GameSpells.__initialized = true
end

function GameSpells.terminate()
  GameSpells.__initialized = false
end

-- words: string (ex.: 'exura' ou 'exiva "Alvo"')
-- opts: { parameter = string, effectId = number, durationMs = number }
function GameSpells.castSpell(words, opts)
  if not words or words == '' then return end
  if not g_game.isOnline() then return end

  local parameter = opts and opts.parameter or nil
  local durationMs = (opts and opts.durationMs) or DEFAULT_PRECAST_DURATION

  -- Resolve effectId (prioridade: opts.effectId > por palavras > por grupo)
  local effectId = opts and opts.effectId or resolvePrecastEffectId(words)

  -- Dispara visual de pré-cast local
  attachPrecast(effectId, durationMs)

  -- Envia fala para servidor (protocolo oficial TALKTYPE_SPELL_USE)
  local text = buildTalkText(words, parameter)
  g_game.talk(text)
end

-- Documentação do mapeamento básico:
-- - WordsPrecastEffect: mapa explícito words → effectId (prioritário)
-- - GroupPrecastEffect: fallback por grupo primário do spell (Attack/Healing/Support)
-- Ajuste conforme seu catálogo de AttachedEffects:
--   3 = 'Angel Light' (ThingCategoryEffect)
--   7 = 'Pentagram Aura' (ThingExternalTexture)
--   8 = 'Ki' (ThingExternalTexture)

