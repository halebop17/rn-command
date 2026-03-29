--[[============================================================
  RN Commander for Renoise  v1.22
  Full Reform-style transforms + Effect commands + Quick Flicks
============================================================]]--

-- ============================================================
-- DATA
-- ============================================================

local EFFECT_COLUMNS = {
  { label="-Axy", cmd="0A", desc="Set arpeggio, x/y = first/second note offset in semitones" },
  { label="-Uxx", cmd="0U", desc="Slide Pitch up by xx 1/16ths of a semitone" },
  { label="-Dxx", cmd="0D", desc="Slide Pitch down by xx 1/16ths of a semitone" },
  { label="-Gxx", cmd="0G", desc="Glide towards given note by xx 1/16ths of a semitone" },
  { label="-Ixx", cmd="0I", desc="Fade Volume in by xx volume units" },
  { label="-Oxx", cmd="0O", desc="Fade Volume out by xx volume units" },
  { label="-Cxy", cmd="0C", desc="Cut volume to x after y ticks (x = volume factor: 0=0%, F=100%)" },
  { label="-Qxx", cmd="0Q", desc="Delay note by xx ticks" },
  { label="-Mxx", cmd="0M", desc="Set note volume to xx" },
  { label="-Sxx", cmd="0S", desc="Trigger sample slice number xx or offset xx" },
  { label="-Bxx", cmd="0B", desc="Play Sample Backwards (B00) or forwards again (B01)" },
  { label="-Rxy", cmd="0R", desc="Retrigger line every y ticks with volume factor x" },
  { label="-Yxx", cmd="0Y", desc="Maybe trigger line with probability xx, 00 = mutually exclusive" },
  { label="-Zxx", cmd="0Z", desc="Trigger Phrase xx (01-7E), 00 = none, 7F = keymap" },
  { label="-Vxy", cmd="0V", desc="Set Vibrato x = speed, y = depth; x=(0-F); y=(0-F)" },
  { label="-Txy", cmd="0T", desc="Set Tremolo x = speed, y = depth" },
  { label="-Nxy", cmd="0N", desc="Set Auto Pan, x = speed, y = depth" },
  { label="-Exx", cmd="0E", desc="Set Active Sample Envelope's Position to Offset XX" },
  { label="-Lxx", cmd="0L", desc="Set Track Volume Level, 00 = -INF, FF = +3dB" },
  { label="-Pxx", cmd="0P", desc="Set Track Pan, 00 = full left, 80 = center, FF = full right" },
  { label="-Wxx", cmd="0W", desc="Set Track Surround Width, 00 = Min, FF = Max" },
  { label="-Jxx", cmd="0J", desc="Set Track Routing, 01 upwards = hw channels, FF = parent groups" },
  { label="-Xxx", cmd="0X", desc="Stop all notes and FX (xx = 00), or only effect xx (xx > 00)" },
  { label="ZTxx", cmd="ZT", desc="Set tempo to xx BPM (14-FF, 00 = stop song)" },
  { label="ZLxx", cmd="ZL", desc="Set Lines Per Beat (LPB) to xx lines" },
  { label="ZKxx", cmd="ZK", desc="Set Ticks Per Line (TPL) to xx ticks (01-10)" },
  { label="ZGxx", cmd="ZG", desc="Enable (xx = 01) or disable (xx = 00) Groove" },
  { label="ZBxx", cmd="ZB", desc="Break pattern and jump to line xx in next" },
  { label="ZDxx", cmd="ZD", desc="Delay (pause) pattern for xx lines" },
}

local SAMPLE_FX = {
  { label="-Axy", cmd="0A", desc="Set arpeggio, x/y = first/second note offset in semitones" },
  { label="-Uxx", cmd="0U", desc="Slide Pitch up by xx 1/16ths of a semitone" },
  { label="-Dxx", cmd="0D", desc="Slide Pitch down by xx 1/16ths of a semitone" },
  { label="-Gxx", cmd="0G", desc="Glide towards given note by xx 1/16ths of a semitone" },
  { label="-Vxy", cmd="0V", desc="Set Vibrato x = speed, y = depth; x=(0-F); y=(0-F)" },
  { label="-Ixx", cmd="0I", desc="Fade Volume in by xx volume units" },
  { label="-Oxx", cmd="0O", desc="Fade Volume out by xx volume units" },
  { label="-Txy", cmd="0T", desc="Set Tremolo x = speed, y = depth" },
  { label="-Cxy", cmd="0C", desc="Cut volume to x after y ticks (x = volume factor: 0=0%, F=100%)" },
  { label="-Sxx", cmd="0S", desc="Trigger sample slice number xx or offset xx" },
  { label="-Bxx", cmd="0B", desc="Play Sample Backwards (B00) or forwards again (B01)" },
  { label="-Exx", cmd="0E", desc="Set Active Sample Envelope's Position to Offset XX" },
  { label="-Nxy", cmd="0N", desc="Set Auto Pan, x = speed, y = depth" },
}

-- ============================================================
-- HELPERS
-- ============================================================

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

local function hex2(n)
  return string.format("%02X", clamp(math.floor(n + 0.5), 0, 255))
end

local function status(msg)
  renoise.app():show_status(msg)
end

local function ensure_ecol()
  local t = renoise.song().selected_track
  if t and t.visible_effect_columns < 1 then
    t.visible_effect_columns = 1
  end
end

-- ============================================================
-- WRITE MODE
-- ============================================================

local write_mode = 1  -- 1 = effect columns, 2 = sample FX note sub-col

local g_rand = {
  enabled = true,
  fill_prob = 50,
  whole_if_none = false,
  minmax_only = false,
  dont_overwrite = false,
  lock_current_effects = false,
  only_rows_with_effects = false,
  only_rows_with_notes = false,
  min_val = 0,
  max_val = 255,
}

-- Get note column via indices (works even when dialog has focus)
local function get_selected_note_col()
  local song = renoise.song()
  local ti = song.selected_track_index
  local li = song.selected_line_index
  local ci = song.selected_note_column_index
  if ti < 1 or li < 1 or ci < 1 then return nil end
  local tobj = song:track(ti)
  if tobj.type ~= renoise.Track.TRACK_TYPE_SEQUENCER then return nil end
  if ci > tobj.visible_note_columns then return nil end
  return song.selected_pattern:track(ti):line(li):note_column(ci)
end

-- Get effect column via indices (works even when dialog has focus)
local function get_selected_effect_col()
  local song = renoise.song()
  local ti = song.selected_track_index
  local li = song.selected_line_index
  local ci = song.selected_effect_column_index
  if ti < 1 or li < 1 or ci < 1 then return nil end
  local tobj = song:track(ti)
  if tobj.type ~= renoise.Track.TRACK_TYPE_SEQUENCER then return nil end
  ensure_ecol()
  return song.selected_pattern:track(ti):line(li):effect_column(ci)
end

local function insert_effect_cmd(cmd, amount_str)
  amount_str = amount_str or "00"
  local base_amt = tonumber(amount_str, 16) or 0
  local song = renoise.song()
  local ti = song.selected_track_index
  local li = song.selected_line_index
  if ti < 1 or li < 1 then
    status("No track/line selected.")
    return
  end

  local tr = song:track(ti)
  if tr.type ~= renoise.Track.TRACK_TYPE_SEQUENCER then
    status("Select a sequencer track first.")
    return
  end

  local sl, el = li, li
  local sel = song.selection_in_pattern
  if sel and sel.start_track <= ti and sel.end_track >= ti then
    sl, el = sel.start_line, sel.end_line
  elseif g_rand.enabled and g_rand.whole_if_none then
    sl, el = 1, song.selected_pattern.number_of_lines
  end

  local function line_has_note(line)
    for ci = 1, tr.visible_note_columns do
      if not line:note_column(ci).is_empty then return true end
    end
    return false
  end

  local function line_has_fx(line)
    for ci = 1, tr.visible_effect_columns do
      if not line:effect_column(ci).is_empty then return true end
    end
    for ci = 1, tr.visible_note_columns do
      local n = line:note_column(ci)
      if n.effect_number_string ~= ".." and n.effect_number_string ~= "00" then
        return true
      end
    end
    return false
  end

  local function should_process_line(line)
    if g_rand.enabled then
      if g_rand.only_rows_with_notes and (not line_has_note(line)) then return false end
      if g_rand.only_rows_with_effects and (not line_has_fx(line)) then return false end
    end
    return true
  end

  local function pick_amount(default_amt)
    if not g_rand.enabled then return default_amt end
    if g_rand.minmax_only then
      return (math.random() < 0.5) and g_rand.min_val or g_rand.max_val
    end
    local lo = math.min(g_rand.min_val, g_rand.max_val)
    local hi = math.max(g_rand.min_val, g_rand.max_val)
    return math.random(lo, hi)
  end

  local pt = song.selected_pattern:track(ti)
  local changed = 0

  if write_mode == 1 then
    ensure_ecol()
    local ci = song.selected_effect_column_index
    if ci < 1 then ci = 1 end
    if ci > tr.visible_effect_columns then ci = 1 end

    for row = sl, el do
      local line = pt:line(row)
      if should_process_line(line) then
        local ecol = line:effect_column(ci)
        if (not g_rand.enabled) or (not g_rand.dont_overwrite) or ecol.is_empty then
          local do_fill = (not g_rand.enabled) or (math.random(100) <= g_rand.fill_prob)
          if do_fill then
            ecol.number_string = cmd
            ecol.amount_string = hex2(pick_amount(base_amt))
          else
            ecol:clear()
          end
          changed = changed + 1
        end
      end
    end
    status(string.format("Effect col: %s on %d row(s).", cmd, changed))
  else
    local ci = song.selected_note_column_index
    if ci < 1 then ci = 1 end
    if tr.visible_note_columns < 1 then tr.visible_note_columns = 1 end
    if ci > tr.visible_note_columns then ci = 1 end

    for row = sl, el do
      local line = pt:line(row)
      if should_process_line(line) then
        local ncol = line:note_column(ci)
        local has_fx = (ncol.effect_number_string ~= ".." and ncol.effect_number_string ~= "00")
        if (not g_rand.enabled) or (not g_rand.dont_overwrite) or (not has_fx) then
          local do_fill = (not g_rand.enabled) or (math.random(100) <= g_rand.fill_prob)
          if do_fill then
            ncol.effect_number_string = cmd
            ncol.effect_amount_string = hex2(pick_amount(base_amt))
          else
            ncol.effect_number_string = ".."
            ncol.effect_amount_string = "00"
          end
          changed = changed + 1
        end
      end
    end
    status(string.format("Sample FX: %s on %d row(s).", cmd, changed))
  end
end

-- ============================================================
-- COL VALUES
-- ============================================================

local function set_volume(val)
  local song = renoise.song()
  local ti = song.selected_track_index
  local li = song.selected_line_index
  if ti < 1 or li < 1 then
    status("Select a track/line first.")
    return
  end

  local tr = song:track(ti)
  if tr.type ~= renoise.Track.TRACK_TYPE_SEQUENCER then
    status("Place cursor on a sequencer track first.")
    return
  end
  if tr.visible_note_columns < 1 then
    status("No note columns visible.")
    return
  end

  local ci = song.selected_note_column_index
  if ci < 1 or ci > tr.visible_note_columns then ci = 1 end

  local sl, el = li, li
  local sel = song.selection_in_pattern
  if sel and sel.start_track <= ti and sel.end_track >= ti then
    sl, el = sel.start_line, sel.end_line
  end

  local pt = song.selected_pattern:track(ti)
  local changed = 0
  for row = sl, el do
    local ncol = pt:line(row):note_column(ci)
    if not ncol.is_empty then
      ncol.volume_value = val
      changed = changed + 1
    end
  end
  if changed == 0 then
    pt:line(li):note_column(ci).volume_value = val
    changed = 1
  end
  status(string.format("Volume = %s on %d row(s)", hex2(val), changed))
end

local function set_panning(val)
  local song = renoise.song()
  local ti = song.selected_track_index
  local li = song.selected_line_index
  if ti < 1 or li < 1 then
    status("Select a track/line first.")
    return
  end

  local tr = song:track(ti)
  if tr.type ~= renoise.Track.TRACK_TYPE_SEQUENCER then
    status("Place cursor on a sequencer track first.")
    return
  end
  if tr.visible_note_columns < 1 then
    status("No note columns visible.")
    return
  end

  local ci = song.selected_note_column_index
  if ci < 1 or ci > tr.visible_note_columns then ci = 1 end

  local sl, el = li, li
  local sel = song.selection_in_pattern
  if sel and sel.start_track <= ti and sel.end_track >= ti then
    sl, el = sel.start_line, sel.end_line
  end

  local pt = song.selected_pattern:track(ti)
  local changed = 0
  for row = sl, el do
    local ncol = pt:line(row):note_column(ci)
    if not ncol.is_empty then
      ncol.panning_value = val
      changed = changed + 1
    end
  end
  if changed == 0 then
    pt:line(li):note_column(ci).panning_value = val
    changed = 1
  end
  status(string.format("Panning = %s on %d row(s)", hex2(val), changed))
end

local function set_delay(val)
  local song = renoise.song()
  local ti = song.selected_track_index
  local li = song.selected_line_index
  if ti < 1 or li < 1 then
    status("Select a track/line first.")
    return
  end

  local tr = song:track(ti)
  if tr.type ~= renoise.Track.TRACK_TYPE_SEQUENCER then
    status("Place cursor on a sequencer track first.")
    return
  end
  if tr.visible_note_columns < 1 then
    status("No note columns visible.")
    return
  end

  local ci = song.selected_note_column_index
  if ci < 1 or ci > tr.visible_note_columns then ci = 1 end

  local sl, el = li, li
  local sel = song.selection_in_pattern
  if sel and sel.start_track <= ti and sel.end_track >= ti then
    sl, el = sel.start_line, sel.end_line
  end

  local pt = song.selected_pattern:track(ti)
  local changed = 0
  for row = sl, el do
    local ncol = pt:line(row):note_column(ci)
    if not ncol.is_empty then
      ncol.delay_value = val
      changed = changed + 1
    end
  end
  if changed == 0 then
    pt:line(li):note_column(ci).delay_value = val
    changed = 1
  end
  status(string.format("Delay = %s on %d row(s)", hex2(val), changed))
end

local function set_fx_amount(val)
  local song = renoise.song()
  local ti = song.selected_track_index
  local li = song.selected_line_index
  if ti < 1 or li < 1 then
    status("Select a track/line first.")
    return
  end

  local tr = song:track(ti)
  if tr.type ~= renoise.Track.TRACK_TYPE_SEQUENCER then
    status("Place cursor on a sequencer track first.")
    return
  end

  ensure_ecol()
  local ci = song.selected_effect_column_index
  if ci < 1 or ci > tr.visible_effect_columns then ci = 1 end

  local sl, el = li, li
  local sel = song.selection_in_pattern
  if sel and sel.start_track <= ti and sel.end_track >= ti then
    sl, el = sel.start_line, sel.end_line
  end

  local changed = 0
  local pt = song.selected_pattern:track(ti)
  for row = sl, el do
    local ecol = pt:line(row):effect_column(ci)
    if not ecol.is_empty then
      ecol.amount_string = hex2(val)
      changed = changed + 1
    end
  end

  if changed == 0 then
    -- Fallback to current cell so slider always does something visible.
    local ecol = pt:line(li):effect_column(ci)
    ecol.amount_string = hex2(val)
    changed = 1
  end
  status(string.format("FX Amount = %s on %d row(s)", hex2(val), changed))
end

local function set_sample_fx_amount(val)
  local song = renoise.song()
  local ti = song.selected_track_index
  local li = song.selected_line_index
  if ti < 1 or li < 1 then
    status("Select a track/line first.")
    return
  end

  local tr = song:track(ti)
  if tr.type ~= renoise.Track.TRACK_TYPE_SEQUENCER then
    status("Place cursor on a sequencer track first.")
    return
  end
  if tr.visible_note_columns < 1 then
    status("No note columns visible.")
    return
  end

  local ci = song.selected_note_column_index
  if ci < 1 or ci > tr.visible_note_columns then ci = 1 end

  local sl, el = li, li
  local sel = song.selection_in_pattern
  if sel and sel.start_track <= ti and sel.end_track >= ti then
    sl, el = sel.start_line, sel.end_line
  end

  local changed = 0
  local pt = song.selected_pattern:track(ti)
  for row = sl, el do
    local ncol = pt:line(row):note_column(ci)
    local has_fx = (ncol.effect_number_string ~= ".." and ncol.effect_number_string ~= "00")
    if has_fx then
      ncol.effect_amount_string = hex2(val)
      changed = changed + 1
    end
  end

  if changed == 0 then
    -- Fallback to current note column so slider always does something visible.
    local ncol = pt:line(li):note_column(ci)
    ncol.effect_amount_string = hex2(val)
    changed = 1
  end
  status(string.format("Sample FX Amount = %s on %d row(s)", hex2(val), changed))
end

-- ============================================================
-- NOTE TRANSFORM CORE
-- ============================================================

local function get_sel()
  local sel = renoise.song().selection_in_pattern
  if not sel then return nil end
  return sel.start_line, sel.end_line, sel.start_track
end

local function get_pt(ti)
  return renoise.song().selected_pattern:track(ti)
end

local function collect_notes(ti, sl, el)
  local pt   = get_pt(ti)
  local nc   = renoise.song():track(ti).visible_note_columns
  local out  = {}
  for li = sl, el do
    for ci = 1, nc do
      local col = pt:line(li):note_column(ci)
      if not col.is_empty then
        out[#out+1] = {
          line=li, col=ci,
          note=col.note_value,  vol=col.volume_value,
          pan=col.panning_value, delay=col.delay_value,
          inst=col.instrument_value,
          fx_num=col.effect_number_string, fx_amt=col.effect_amount_string,
        }
      end
    end
  end
  return out
end

-- Collect effect column data across selection
local function collect_fx(ti, sl, el)
  local pt  = get_pt(ti)
  local ec  = renoise.song():track(ti).visible_effect_columns
  local out = {}
  for li = sl, el do
    for ci = 1, ec do
      local col = pt:line(li):effect_column(ci)
      if not col.is_empty then
        out[#out+1] = {
          line=li, col=ci,
          num=col.number_string,
          amt=col.amount_value,
        }
      end
    end
  end
  return out
end

local function randomize_effect_values(opts)
  local song = renoise.song()
  local ti = song.selected_track_index
  if ti < 1 then status("Select a track first."); return end

  local tr = song:track(ti)
  if tr.type ~= renoise.Track.TRACK_TYPE_SEQUENCER then
    status("Randomizer works on sequencer tracks only.")
    return
  end

  local sl, el = nil, nil
  local sel = song.selection_in_pattern
  if sel and sel.start_track <= ti and sel.end_track >= ti then
    sl, el = sel.start_line, sel.end_line
  elseif opts.whole_if_none then
    sl, el = 1, song.selected_pattern.number_of_lines
  else
    status("Select a range first, or enable whole-track mode.")
    return
  end

  local pt = get_pt(ti)
  local nc = tr.visible_note_columns
  local ec = tr.visible_effect_columns

  local function row_has_note(line)
    for ci = 1, nc do
      if not line:note_column(ci).is_empty then return true end
    end
    return false
  end

  local function row_has_fx(line)
    for ci = 1, ec do
      if not line:effect_column(ci).is_empty then return true end
    end
    for ci = 1, nc do
      local n = line:note_column(ci)
      if n.effect_number_string ~= ".." and n.effect_number_string ~= "00" then
        return true
      end
    end
    return false
  end

  local function rand_amount()
    if opts.minmax_only then
      return (math.random() < 0.5) and opts.min_val or opts.max_val
    end
    if opts.max_val < opts.min_val then return opts.min_val end
    return math.random(opts.min_val, opts.max_val)
  end

  local changed = 0
  local visited = 0
  for li = sl, el do
    local line = pt:line(li)
    if (not opts.only_rows_with_notes or row_has_note(line))
      and (not opts.only_rows_with_effects or row_has_fx(line)) then

      for ci = 1, ec do
        local c = line:effect_column(ci)
        if not c.is_empty then
          visited = visited + 1
          if opts.lock_current_effects then
            -- Lock presence: never add/remove, always re-randomize current effect amounts.
            c.amount_value = rand_amount()
            changed = changed + 1
          else
            if math.random(100) <= opts.fill_prob then
              if (not opts.dont_overwrite) or c.amount_value == 0 then
                c.amount_value = rand_amount()
                changed = changed + 1
              end
            elseif not opts.dont_overwrite then
              c:clear()
              changed = changed + 1
            end
          end
        end
      end

      for ci = 1, nc do
        local n = line:note_column(ci)
        if n.effect_number_string ~= ".." and n.effect_number_string ~= "00" then
          visited = visited + 1
          if opts.lock_current_effects then
            -- Lock presence: never add/remove, always re-randomize current sample-FX amounts.
            n.effect_amount_value = rand_amount()
            changed = changed + 1
          else
            if math.random(100) <= opts.fill_prob then
              if (not opts.dont_overwrite) or n.effect_amount_value == 0 then
                n.effect_amount_value = rand_amount()
                changed = changed + 1
              end
            elseif not opts.dont_overwrite then
              n.effect_number_string = ".."
              n.effect_amount_string = "00"
              changed = changed + 1
            end
          end
        end
      end
    end
  end

  status(string.format("Randomized %d of %d effect values.", changed, visited))
end

local function write_note(ti, e)
  local col = get_pt(ti):line(e.line):note_column(e.col)
  col.note_value=e.note; col.volume_value=e.vol
  col.panning_value=e.pan; col.delay_value=e.delay
  col.instrument_value=e.inst
  col.effect_number_string=e.fx_num; col.effect_amount_string=e.fx_amt
end

local function write_fx(ti, e)
  local col = get_pt(ti):line(e.line):effect_column(e.col)
  col.number_string=e.num; col.amount_value=e.amt
end

local function clear_range(ti, sl, el)
  for li = sl, el do get_pt(ti):line(li):clear() end
end

-- ============================================================
-- CURVE FUNCTIONS
-- Apply a curve to a 0..1 input, returns 0..1
-- ============================================================

local CURVE_TYPES = { "Linear", "Ease In", "Ease Out", "S-Curve", "Sine", "Inverse" }

local function apply_curve(t, curve_idx)
  if curve_idx == 1 then -- Linear
    return t
  elseif curve_idx == 2 then -- Ease In (exponential)
    return t * t
  elseif curve_idx == 3 then -- Ease Out
    return 1 - (1-t)*(1-t)
  elseif curve_idx == 4 then -- S-Curve
    return t * t * (3 - 2*t)
  elseif curve_idx == 5 then -- Sine
    return (1 - math.cos(t * math.pi)) / 2
  elseif curve_idx == 6 then -- Inverse
    return 1 - t
  end
  return t
end

-- ============================================================
-- ANCHOR OPTIONS
-- ============================================================

local ANCHOR_TYPES = { "Start", "End", "Center", "First Note" }

local function get_anchor(notes, sl, el, anchor_idx)
  if anchor_idx == 1 then return sl
  elseif anchor_idx == 2 then return el
  elseif anchor_idx == 3 then return math.floor((sl + el) / 2)
  elseif anchor_idx == 4 then return notes[1] and notes[1].line or sl
  end
  return sl
end

-- ============================================================
-- COLLISION CONTROL OPTIONS
-- ============================================================

local COLLISION_TYPES = { "Keep Earlier", "Keep Later", "Keep Selected", "Keep Unselected" }

-- Resolve collisions in a list of notes placed at new lines
-- collision_idx: 1=keep earlier, 2=keep later, 3=keep first-listed (selected), 4=keep second-listed
local function resolve_collisions(notes, collision_idx)
  local by_line_col = {}
  local result = {}
  for _, n in ipairs(notes) do
    local key = n.line .. ":" .. n.col
    if not by_line_col[key] then
      by_line_col[key] = n
      result[#result+1] = n
    else
      local existing = by_line_col[key]
      local keep
      if collision_idx == 1 then -- keep earlier (lower original line)
        keep = (existing.orig_line <= n.orig_line) and existing or n
      elseif collision_idx == 2 then -- keep later
        keep = (existing.orig_line >= n.orig_line) and existing or n
      elseif collision_idx == 3 then -- keep selected (first encountered = "selected")
        keep = existing
      else -- keep unselected (second encountered)
        keep = n
      end
      -- replace in result
      for i, r in ipairs(result) do
        if r.line == existing.line and r.col == existing.col then
          result[i] = keep
          by_line_col[key] = keep
          break
        end
      end
    end
  end
  return result
end

-- ============================================================
-- OVERFLOW
-- When notes collide, push overflow into next available column
-- ============================================================

local function apply_overflow(notes, ti, total_lines)
  local nc = renoise.song():track(ti).visible_note_columns
  -- Build occupied map: line -> list of cols used
  local occupied = {}
  local result = {}
  for _, n in ipairs(notes) do
    local li = n.line
    if not occupied[li] then occupied[li] = {} end
    -- find first free column on this line
    local placed = false
    for ci = 1, nc do
      local taken = false
      for _, used_col in ipairs(occupied[li]) do
        if used_col == ci then taken = true; break end
      end
      if not taken then
        n.col = ci
        occupied[li][#occupied[li]+1] = ci
        result[#result+1] = n
        placed = true
        break
      end
    end
    if not placed then
      -- all columns full on this line — skip (column limit reached)
      status("Warning: some notes dropped, all columns full on line " .. li)
    end
  end
  return result
end

-- ============================================================
-- TRANSFORM FUNCTIONS
-- ============================================================

-- Current transform settings (module-level, updated by GUI)
local g_anchor    = 1   -- index into ANCHOR_TYPES
local g_collision = 1   -- index into COLLISION_TYPES
local g_overflow  = false
local g_curve     = 1   -- index into CURVE_TYPES

local function reform_redistribute()
  local sl, el, ti = get_sel()
  if not sl then status("Select notes first."); return end
  local notes = collect_notes(ti, sl, el)
  if #notes < 2 then status("Need 2+ notes."); return end
  local anchor = get_anchor(notes, sl, el, g_anchor)
  -- Redistribute within the range sl..el using curve
  local span = el - sl
  for i, n in ipairs(notes) do
    local t = (i-1) / (#notes-1)
    t = apply_curve(t, g_curve)
    n.orig_line = n.line
    n.line = clamp(sl + math.floor(t * span + 0.5), sl, el)
  end
  if g_overflow then
    notes = apply_overflow(notes, ti, renoise.song().selected_pattern.number_of_lines)
  else
    notes = resolve_collisions(notes, g_collision)
  end
  clear_range(ti, sl, el)
  for _, n in ipairs(notes) do write_note(ti, n) end
  status("Redistributed " .. #notes .. " notes.")
end

local g_shift_amt = 1

local function reform_shift(amount)
  local sl, el, ti = get_sel()
  if not sl then status("Select notes first."); return end
  local notes = collect_notes(ti, sl, el)
  if #notes == 0 then return end
  local total = renoise.song().selected_pattern.number_of_lines
  for _, n in ipairs(notes) do
    n.orig_line = n.line
    n.line = ((n.line - 1 + amount) % total) + 1
  end
  if g_overflow then
    notes = apply_overflow(notes, ti, total)
  else
    notes = resolve_collisions(notes, g_collision)
  end
  clear_range(ti, sl, el)
  for _, n in ipairs(notes) do write_note(ti, n) end
  status("Shifted " .. amount .. " lines.")
end

local g_scale_val = 10  -- factor = g_scale_val / 10

local function reform_scale(factor)
  local sl, el, ti = get_sel()
  if not sl then status("Select notes first."); return end
  local notes = collect_notes(ti, sl, el)
  if #notes < 2 then status("Need 2+ notes."); return end
  local anchor = get_anchor(notes, sl, el, g_anchor)
  local total = renoise.song().selected_pattern.number_of_lines
  for _, n in ipairs(notes) do
    n.orig_line = n.line
    n.line = clamp(anchor + math.floor((n.line - anchor) * factor + 0.5), 1, total)
  end
  if g_overflow then
    notes = apply_overflow(notes, ti, total)
  else
    notes = resolve_collisions(notes, g_collision)
  end
  clear_range(ti, sl, el)
  for _, n in ipairs(notes) do write_note(ti, n) end
  status(string.format("Scaled x%.2f (anchor: %s).", factor, ANCHOR_TYPES[g_anchor]))
end

local function reform_condense()
  local sl, el, ti = get_sel()
  if not sl then status("Select notes first."); return end
  local pt   = get_pt(ti)
  local nc   = renoise.song():track(ti).visible_note_columns
  local by_line = {}
  for li = sl, el do
    by_line[li] = {}
    for ci = 1, nc do
      local col = pt:line(li):note_column(ci)
      if not col.is_empty then
        by_line[li][#by_line[li]+1] = {
          note=col.note_value, vol=col.volume_value,
          pan=col.panning_value, delay=col.delay_value,
          inst=col.instrument_value,
          fx_num=col.effect_number_string, fx_amt=col.effect_amount_string,
        }
      end
    end
    pt:line(li):clear()
  end
  for li = sl, el do
    for i, n in ipairs(by_line[li]) do
      if i <= nc then
        local col = pt:line(li):note_column(i)
        col.note_value=n.note; col.volume_value=n.vol
        col.panning_value=n.pan; col.delay_value=n.delay
        col.instrument_value=n.inst
        col.effect_number_string=n.fx_num; col.effect_amount_string=n.fx_amt
      end
    end
  end
  status("Condensed.")
end

-- Generic value remap with curve across a selection
local function remap_values(values, lo, hi, curve_idx)
  if #values == 0 then return end
  local count = #values
  for i, entry in ipairs(values) do
    local t = (count == 1) and 0.5 or (i-1)/(count-1)
    t = apply_curve(t, curve_idx)
    entry.new_val = math.floor(lo + t*(hi-lo) + 0.5)
  end
end

local g_vol_lo = 0;  local g_vol_hi = 127
local g_pan_lo = 0;  local g_pan_hi = 255
local g_fx_lo  = 0;  local g_fx_hi  = 255

local function reform_vol_remap()
  local sl, el, ti = get_sel()
  if not sl then status("Select notes first."); return end
  local notes = collect_notes(ti, sl, el)
  local valid = {}
  for _, n in ipairs(notes) do
    if n.vol ~= 255 then valid[#valid+1] = { note=n, new_val=0 } end
  end
  if #valid == 0 then status("No volume data in selection."); return end
  remap_values(valid, g_vol_lo, g_vol_hi, g_curve)
  for _, v in ipairs(valid) do
    v.note.vol = v.new_val
    write_note(ti, v.note)
  end
  status(string.format("Volume: %s->%s across %d notes (%s curve).",
    hex2(g_vol_lo), hex2(g_vol_hi), #valid, CURVE_TYPES[g_curve]))
end

local function reform_pan_remap()
  local sl, el, ti = get_sel()
  if not sl then status("Select notes first."); return end
  local notes = collect_notes(ti, sl, el)
  local valid = {}
  for _, n in ipairs(notes) do
    if n.pan ~= 255 then valid[#valid+1] = { note=n, new_val=0 } end
  end
  if #valid == 0 then status("No panning data in selection."); return end
  remap_values(valid, g_pan_lo, g_pan_hi, g_curve)
  for _, v in ipairs(valid) do
    v.note.pan = v.new_val
    write_note(ti, v.note)
  end
  status(string.format("Pan: %s->%s across %d notes (%s curve).",
    hex2(g_pan_lo), hex2(g_pan_hi), #valid, CURVE_TYPES[g_curve]))
end

-- FX Transform: remap effect column amount values across selection
local function reform_fx_remap()
  local sl, el, ti = get_sel()
  if not sl then status("Select notes first."); return end
  local fxlist = collect_fx(ti, sl, el)
  if #fxlist == 0 then status("No effect data in selection."); return end
  local valid = {}
  for _, f in ipairs(fxlist) do valid[#valid+1] = { fx=f, new_val=0 } end
  remap_values(valid, g_fx_lo, g_fx_hi, g_curve)
  for _, v in ipairs(valid) do
    v.fx.amt = v.new_val
    write_fx(ti, v.fx)
  end
  status(string.format("FX Amount: %s->%s across %d effects (%s curve).",
    hex2(g_fx_lo), hex2(g_fx_hi), #valid, CURVE_TYPES[g_curve]))
end

-- ============================================================
-- QUICK FLICKS
-- ============================================================

local function qf_ramp(dir)
  local sl, el, ti = get_sel()
  if not sl then status("Select a range first."); return end
  ensure_ecol()
  local pt    = get_pt(ti)
  local steps = el - sl + 1
  local cmd   = (dir=="up") and "0I" or "0O"
  for li = sl, el do
    local t   = (steps==1) and 0.5 or (li-sl)/(steps-1)
    local val = math.floor((dir=="up" and t or (1-t)) * 255)
    local ecol = pt:line(li):effect_column(1)
    ecol.number_string = cmd
    ecol.amount_string = hex2(val)
  end
  status("Volume ramp " .. dir .. " (" .. cmd .. ") in effect column.")
end

local function qf_gate(pat_str)
  -- gate=1 (open): clear effect column so note plays freely
  -- gate=0 (closed): write C00 to cut note immediately (matches Paketti)
  local sl, el, ti = get_sel()
  if not sl then status("Select a range first."); return end
  ensure_ecol()
  local pt   = get_pt(ti)
  local plen = #pat_str
  for li = sl, el do
    local idx  = ((li-sl) % plen) + 1
    local gate = tonumber(pat_str:sub(idx,idx))
    local ecol = pt:line(li):effect_column(1)
    if gate == 0 then
      ecol.number_string = "0C"
      ecol.amount_string = "00"
    else
      ecol:clear()
    end
  end
  status("Gate " .. pat_str .. " applied.")
end

local function qf_cut(cmd, amt)
  local sl, el, ti = get_sel()
  if not sl then status("Select a range first."); return end
  ensure_ecol()
  local pt = get_pt(ti)
  for li = sl, el do
    local ecol = pt:line(li):effect_column(1)
    ecol.number_string = cmd
    ecol.amount_string = amt
  end
  status("Cut: " .. cmd .. amt)
end

local function qf_retrig(cmd, amt)
  local sl, el, ti = get_sel()
  if not sl then status("Select a range first."); return end
  ensure_ecol()
  local pt = get_pt(ti)
  for li = sl, el do
    local ecol = pt:line(li):effect_column(1)
    ecol.number_string = cmd
    ecol.amount_string = amt
  end
  status("Retrig: " .. cmd .. amt)
end

local function qf_retrig_vol_ramp(dir)
  local sl, el, ti = get_sel()
  if not sl then status("Select a range first."); return end
  ensure_ecol()
  local pt    = get_pt(ti)
  local steps = el - sl + 1
  for li = sl, el do
    local i = li - sl
    local t = (steps == 1) and 0.5 or i / (steps - 1)
    local x_up = math.floor(t * 15)
    local x = (dir == "up") and x_up or (15 - x_up)
    local amt = x * 16 + 4  -- y nibble fixed at 4 (tick interval)
    local ecol = pt:line(li):effect_column(1)
    ecol.number_string = "0R"
    ecol.amount_string = hex2(amt)
  end
  status("Retrig Vol " .. dir)
end

local function qf_slice(mode)
  local sl, el, ti = get_sel()
  if not sl then status("Select a range first."); return end
  ensure_ecol()
  local pt    = get_pt(ti)
  local steps = el - sl + 1
  for li = sl, el do
    local idx = li - sl
    local snum
    if mode=="seq" then
      snum = (idx % 16) + 1
    elseif mode=="rev" then
      snum = ((16 - (idx % 16) - 1) % 16) + 1
    else
      snum = math.random(1, 16)
    end
    local ecol = pt:line(li):effect_column(1)
    ecol.number_string = "0S"
    ecol.amount_string = hex2(snum)
  end
  status("Slice: " .. mode)
end

-- ============================================================
-- GUI STATE
-- ============================================================

local g_dialog  = nil
local g_vol_val = 64
local g_pan_val = 128
local g_dly_val = 0
local g_fxa_val = 0
local g_sfxa_val = 0

-- ============================================================
-- GUI BUILD
-- ============================================================

local function build_gui()
  local vb = renoise.ViewBuilder()

  -- ── Effect list builder ─────────────────────────────────
  -- Each row: [label button] [hex textfield] [description]
  local function make_fx_list(data)
    local col = vb:column { spacing = 1 }
    for _, e in ipairs(data) do
      local entry = e
      local tf = vb:textfield { text="00", width=34 }
      col:add_child(vb:row {
        vb:button {
          text=entry.label, width=48, height=17,
          notifier = function()
            local n = tonumber(tf.text, 16)
            if n then
              insert_effect_cmd(entry.cmd, hex2(n))
            else
              tf.text = "00"
              status("Invalid hex — reset to 00.")
            end
          end,
        },
        tf,
        vb:text { text=entry.desc, font="mono", height=17 },
      })
    end
    return col
  end

  local fx_col_list  = make_fx_list(EFFECT_COLUMNS)
  local fx_samp_list = make_fx_list(SAMPLE_FX)

  local current_fx_tab = "effect"
  local fx_tab_label   = vb:text { text="Effect Columns  (writes to effect column)", style="strong" }
  local fx_list_holder = vb:column {}
  fx_list_holder:add_child(fx_col_list)

  -- Single switch: controls BOTH which list is shown AND where commands are written
  local tab_switch = vb:switch {
    items = { "Effect Columns", "Sample FX" },
    width = 220,
    value = 1,
    notifier = function(idx)
      local which = (idx == 1) and "effect" or "sample"
      write_mode = idx
      if which == current_fx_tab then return end
      fx_list_holder:remove_child(
        current_fx_tab=="effect" and fx_col_list or fx_samp_list)
      current_fx_tab = which
      fx_list_holder:add_child(
        which=="effect" and fx_col_list or fx_samp_list)
      fx_tab_label.text = (which=="effect")
        and "Effect Columns  (writes to effect column)"
        or  "Sample FX  (writes to note sub-column)"
    end,
  }

  local left_panel = vb:column {
    margin=4, spacing=4,
    tab_switch,
    fx_tab_label,
    fx_list_holder,
  }

  -- ── Column Values panel ─────────────────────────────────
  local vol_txt = vb:text{text="40",width=28,style="strong"}
  local pan_txt = vb:text{text="80",width=28,style="strong"}
  local dly_txt = vb:text{text="00",width=28,style="strong"}
  local fxa_txt = vb:text{text="00",width=28,style="strong"}
  local sfxa_txt = vb:text{text="00",width=28,style="strong"}
  local col_vals_panel = nil

  -- ── Transforms panel (Reform-style) ─────────────────────

  -- Nudge helper: builds a  ◄ [val_label] ►  row
  local function nudge_row(txt_w, get_fn, set_fn, lo, hi)
    return vb:row{ spacing=1,
      vb:button{ text="◄", width=18, height=16,
        notifier=function()
          local v = math.max(lo, get_fn()-1); set_fn(v); txt_w.text=hex2(v)
        end},
      txt_w,
      vb:button{ text="►", width=18, height=16,
        notifier=function()
          local v = math.min(hi, get_fn()+1); set_fn(v); txt_w.text=hex2(v)
        end},
    }
  end

  local overflow_active = false
  local overflow_btn
  local collision_pop = vb:popup{
    items={"◈ Earlier","◈ Later","◈ Keep Sel","◈ Drop Sel"},
    value=1, width=128,
    notifier=function(v) g_collision=v end,
  }
  overflow_btn = vb:button{
    text="⊞ Over", width=66,
    notifier=function()
      overflow_active = not overflow_active
      g_overflow = overflow_active
      overflow_btn.color = overflow_active and {0.2,0.5,0.2} or {0.3,0.3,0.3}
      collision_pop.active = not overflow_active
    end,
  }

  local scale_lbl = vb:text{text="1.0x",   width=56}
  local curve_lbl = vb:text{text="Linear", width=56}
  local shift_lbl = vb:text{text="1 ln",   width=56}

  local vhi_txt = vb:text{text="7F", width=24, style="strong"}
  local vlo_txt = vb:text{text="00", width=24, style="strong"}
  local phi_txt = vb:text{text="FF", width=24, style="strong"}
  local plo_txt = vb:text{text="00", width=24, style="strong"}
  local fhi_txt = vb:text{text="FF", width=24, style="strong"}
  local flo_txt = vb:text{text="00", width=24, style="strong"}

  local transforms_panel = vb:column {
    margin=4, spacing=6,
    vb:text{text="Transforms  (select notes first)", style="strong"},
    vb:space{height=2},

    -- ── Row 1: ↕ Scale  |  ~ Curve  |  ↑↓ Shift ───────────
    vb:row{ spacing=8,

      -- Scale
      vb:column{ spacing=2,
        vb:text{text="↕ Scale"},
        vb:slider{ min=2, max=40, value=10, width=36, height=90,
          notifier=function(v)
            g_scale_val=v; scale_lbl.text=string.format("%.1fx",v/10)
          end},
        scale_lbl,
        vb:row{
          vb:button{text="<", width=27,
            notifier=function() reform_scale(10/g_scale_val) end},
          vb:button{text=">", width=27,
            notifier=function() reform_scale(g_scale_val/10) end},
        },
      },

      -- Curve (◄ ► cycle through types)
      vb:column{ spacing=2,
        vb:text{text="~ Curve"},
        vb:space{height=22},
        curve_lbl,
        vb:space{height=22},
        vb:row{
          vb:button{text="◄", width=27,
            notifier=function()
              g_curve=((g_curve-2)%6)+1; curve_lbl.text=CURVE_TYPES[g_curve]
            end},
          vb:button{text="►", width=27,
            notifier=function()
              g_curve=(g_curve%6)+1; curve_lbl.text=CURVE_TYPES[g_curve]
            end},
        },
      },

      -- Shift
      vb:column{ spacing=2,
        vb:text{text="↑↓ Shift"},
        vb:slider{ min=1, max=32, value=1, width=36, height=90,
          notifier=function(v)
            g_shift_amt=math.floor(v); shift_lbl.text=g_shift_amt.." ln"
          end},
        shift_lbl,
        vb:row{
          vb:button{text="◄", width=27,
            notifier=function() reform_shift(-g_shift_amt) end},
          vb:button{text="►", width=27,
            notifier=function() reform_shift(g_shift_amt) end},
        },
      },
    },

    vb:space{height=4},

    -- ── Row 2: Actions  +  Anchor  +  Collision ────────────
    vb:row{ spacing=3,
      vb:button{text="≡ Redist", width=72, notifier=reform_redistribute},
      overflow_btn,
      vb:button{text="⊟ Cond",  width=64, notifier=reform_condense},
    },
    vb:row{ spacing=4,
      vb:text{text="⚓ Anchor:", width=70},
      vb:popup{ items={"Start","End","Center","1st Note"}, value=1, width=110,
        notifier=function(v) g_anchor=v end},
    },
    vb:row{ spacing=4,
      vb:text{text="Collision:", width=70},
      collision_pop,
    },

    vb:space{height=4},

    -- ── Row 3: VOL | PAN | FX remap ────────────────────────
    vb:row{ spacing=6,

      -- VOL
      vb:column{ spacing=2,
        vb:text{text="VOL"},
        nudge_row(vhi_txt,
          function() return g_vol_hi end,
          function(v) g_vol_hi=v end, 0, 127),
        vb:slider{min=0,max=127,value=127, width=62, height=44,
          notifier=function(v) g_vol_hi=math.floor(v); vhi_txt.text=hex2(g_vol_hi) end},
        vb:slider{min=0,max=127,value=0,   width=62, height=44,
          notifier=function(v) g_vol_lo=math.floor(v); vlo_txt.text=hex2(g_vol_lo) end},
        nudge_row(vlo_txt,
          function() return g_vol_lo end,
          function(v) g_vol_lo=v end, 0, 127),
        vb:button{text="↪ apply", width=62, notifier=reform_vol_remap},
      },

      -- PAN
      vb:column{ spacing=2,
        vb:text{text="PAN"},
        nudge_row(phi_txt,
          function() return g_pan_hi end,
          function(v) g_pan_hi=v end, 0, 255),
        vb:slider{min=0,max=255,value=255, width=62, height=44,
          notifier=function(v) g_pan_hi=math.floor(v); phi_txt.text=hex2(g_pan_hi) end},
        vb:slider{min=0,max=255,value=0,   width=62, height=44,
          notifier=function(v) g_pan_lo=math.floor(v); plo_txt.text=hex2(g_pan_lo) end},
        nudge_row(plo_txt,
          function() return g_pan_lo end,
          function(v) g_pan_lo=v end, 0, 255),
        vb:button{text="↪ apply", width=62, notifier=reform_pan_remap},
      },

      -- FX
      vb:column{ spacing=2,
        vb:text{text="FX"},
        nudge_row(fhi_txt,
          function() return g_fx_hi end,
          function(v) g_fx_hi=v end, 0, 255),
        vb:slider{min=0,max=255,value=255, width=62, height=44,
          notifier=function(v) g_fx_hi=math.floor(v); fhi_txt.text=hex2(g_fx_hi) end},
        vb:slider{min=0,max=255,value=0,   width=62, height=44,
          notifier=function(v) g_fx_lo=math.floor(v); flo_txt.text=hex2(g_fx_lo) end},
        nudge_row(flo_txt,
          function() return g_fx_lo end,
          function(v) g_fx_lo=v end, 0, 255),
        vb:button{text="↪ apply", width=62, notifier=reform_fx_remap},
      },
    },
  }

  -- ── Quick Flicks panel ──────────────────────────────────

  -- Selection range helpers
  local sel_start_val = 0
  local sel_end_val   = 15

  local function total_lines()
    return renoise.song().selected_pattern.number_of_lines
  end

  local function clamp_sel_vals()
    local max0 = math.max(0, total_lines() - 1)
    sel_start_val = clamp(sel_start_val, 0, max0)
    sel_end_val = clamp(sel_end_val, sel_start_val, max0)
  end

  local sel_start_txt = vb:textfield{text="00", width=34}
  local sel_end_txt   = vb:textfield{text="15", width=34}

  local function refresh_sel_fields()
    sel_start_txt.text = string.format("%02d", sel_start_val)
    sel_end_txt.text   = string.format("%02d", sel_end_val)
  end

  local function parse_sel_fields()
    local s = tonumber(sel_start_txt.text, 10)
    local e = tonumber(sel_end_txt.text, 10)
    if s then sel_start_val = math.floor(s) end
    if e then sel_end_val = math.floor(e) end
    clamp_sel_vals()
    refresh_sel_fields()
  end

  local function apply_selection(s, e)
    local song = renoise.song()
    local ti   = song.selected_track_index
    if ti < 1 then status("Select a track first."); return end
    local total = song.selected_pattern.number_of_lines
    s = math.max(1, math.min(s, total))
    e = math.max(s, math.min(e, total))
    song.selection_in_pattern = {
      start_track = ti, end_track = ti,
      start_line  = s,  end_line  = e,
    }
    status("Selected lines " .. s .. "-" .. e)
  end

  local function sel_range(s, e)
    sel_start_val = s - 1
    sel_end_val = e - 1
    clamp_sel_vals()
    refresh_sel_fields()
    apply_selection(s, e)
  end

  local function sel_full()
    local n = renoise.song().selected_pattern.number_of_lines
    sel_range(1, n)
  end

  local function sel_half(which)
    local n = renoise.song().selected_pattern.number_of_lines
    local mid = math.floor(n / 2)
    if which == 1 then sel_range(1, mid)
    else               sel_range(mid + 1, n) end
  end

  local sel_range_panel = vb:column {
    margin=6, spacing=4,
    vb:text{text="Selection Range", style="strong"},
    vb:space{height=2},
    -- Quick quarter buttons
    vb:row{ spacing=4,
      vb:button{text="1-16",  width=55, notifier=function() sel_range(1,  16) end},
      vb:button{text="17-32", width=55, notifier=function() sel_range(17, 32) end},
      vb:button{text="33-48", width=55, notifier=function() sel_range(33, 48) end},
      vb:button{text="49-64", width=55, notifier=function() sel_range(49, 64) end},
    },
    -- Full / halves
    vb:row{ spacing=4,
      vb:button{text="Full",     width=55, notifier=function() sel_full()     end},
      vb:button{text="1st Half", width=65, notifier=function() sel_half(1)    end},
      vb:button{text="2nd Half", width=65, notifier=function() sel_half(2)    end},
    },
    -- Custom start/end
    vb:row{ spacing=4,
      vb:text{text="Start:", width=36},
      vb:button{text="◄", width=18, notifier=function()
        sel_start_val = sel_start_val - 1
        clamp_sel_vals()
        refresh_sel_fields()
      end},
      sel_start_txt,
      vb:button{text="►", width=18, notifier=function()
        sel_start_val = sel_start_val + 1
        clamp_sel_vals()
        refresh_sel_fields()
      end},
      vb:space{width=8},
      vb:text{text="End:", width=30},
      vb:button{text="◄", width=18, notifier=function()
        sel_end_val = sel_end_val - 1
        clamp_sel_vals()
        refresh_sel_fields()
      end},
      sel_end_txt,
      vb:button{text="►", width=18, notifier=function()
        sel_end_val = sel_end_val + 1
        clamp_sel_vals()
        refresh_sel_fields()
      end},
      vb:space{width=4},
      vb:button{text="Select", width=52,
        notifier=function()
          parse_sel_fields()
          apply_selection(sel_start_val + 1, sel_end_val + 1)
        end},
    },
  }

  col_vals_panel = vb:column {
    margin=4, spacing=6,
    sel_range_panel,
    vb:space{height=6},
    vb:text{text="Note Column Values",style="strong"},
    vb:text{text="Drag slider to apply to selected note column",font="italic"},
    vb:space{height=2},
    vb:row{
      vb:text{text="Volume", width=55},
      vb:slider{min=0,max=127,value=64,width=160,
        notifier=function(v) g_vol_val=math.floor(v); vol_txt.text=hex2(v); set_volume(g_vol_val) end},
      vol_txt,
    },
    vb:row{
      vb:text{text="Panning",width=55},
      vb:slider{min=0,max=128,value=128,width=160,
        notifier=function(v) g_pan_val=math.floor(v); pan_txt.text=hex2(v); set_panning(g_pan_val) end},
      pan_txt,
    },
    vb:row{
      vb:text{text="Delay",  width=55},
      vb:slider{min=0,max=255,value=0,width=160,
        notifier=function(v) g_dly_val=math.floor(v); dly_txt.text=hex2(v); set_delay(g_dly_val) end},
      dly_txt,
    },
    vb:space{height=6},
    vb:text{text="Effect Amount",style="strong"},
    vb:text{text="Drag slider to apply to selected effect column",font="italic"},
    vb:space{height=2},
    vb:row{
      vb:text{text="Effect", width=55},
      vb:slider{min=0,max=255,value=0,width=160,
        notifier=function(v) g_fxa_val=math.floor(v); fxa_txt.text=hex2(v); set_fx_amount(g_fxa_val) end},
      fxa_txt,
    },
    vb:row{
      vb:text{text="Sample FX", width=55},
      vb:slider{min=0,max=255,value=0,width=160,
        notifier=function(v) g_sfxa_val=math.floor(v); sfxa_txt.text=hex2(v); set_sample_fx_amount(g_sfxa_val) end},
      sfxa_txt,
    },
  }

  local qf_panel = vb:column {
    margin=4, spacing=6,
    vb:text{text="Volume fade (0I=ramp up, 0O=ramp down):",style="strong"},
    vb:row{
      vb:button{text="Ramp Up",  width=80,
        notifier=function() qf_ramp("up") end},
      vb:button{text="Ramp Down",width=80,
        notifier=function() qf_ramp("down") end},
    },
    vb:space{height=4},
    vb:text{text="Gates (writes 0C to effect col):",style="strong"},
    vb:row{
      vb:button{text="1010",width=50,notifier=function() qf_gate("1010") end},
      vb:button{text="1100",width=50,notifier=function() qf_gate("1100") end},
      vb:button{text="1000",width=50,notifier=function() qf_gate("1000") end},
    },
    vb:space{height=4},
    vb:text{text="Cuts (0Cxy to effect col):",style="strong"},
    vb:row{
      vb:button{text="0C00",width=50,notifier=function() qf_cut("0C","00") end},
      vb:button{text="0C40",width=50,notifier=function() qf_cut("0C","40") end},
      vb:button{text="0C80",width=50,notifier=function() qf_cut("0C","80") end},
      vb:button{text="0CC0",width=50,notifier=function() qf_cut("0C","C0") end},
      vb:button{text="0CF0",width=50,notifier=function() qf_cut("0C","F0") end},
    },
    vb:space{height=4},
    vb:text{text="Retrigger (0Rxy to effect col):",style="strong"},
    vb:row{
      vb:button{text="R01",   width=50,notifier=function() qf_retrig("0R","01") end},
      vb:button{text="R02",   width=50,notifier=function() qf_retrig("0R","02") end},
      vb:button{text="R04",   width=50,notifier=function() qf_retrig("0R","04") end},
      vb:button{text="R08",   width=50,notifier=function() qf_retrig("0R","08") end},
      vb:button{text="Vol Up",width=55,notifier=function() qf_retrig_vol_ramp("up") end},
      vb:button{text="Vol Dn",width=55,notifier=function() qf_retrig_vol_ramp("dn") end},
    },
    vb:space{height=4},
    vb:text{text="Slices (0Sxx to effect col):",style="strong"},
    vb:row{
      vb:button{text="Sequential",width=80,notifier=function() qf_slice("seq") end},
      vb:button{text="Reverse",   width=65,notifier=function() qf_slice("rev") end},
      vb:button{text="Random",    width=65,notifier=function() qf_slice("rnd") end},
    },
  }

  -- ── Randomizer panel ───────────────────────────────────
  local rand_prob_txt = vb:text{text=(g_rand.fill_prob .. "% Fill Probability"), style="strong"}
  local rand_min_txt = vb:text{text=hex2(g_rand.min_val), width=28, style="strong"}
  local rand_max_txt = vb:text{text=hex2(g_rand.max_val), width=28, style="strong"}

  local randomizer_panel = vb:column {
    margin=4, spacing=5,
    vb:text{text="Randomize Effect Value Content", style="strong"},
    vb:row{
      vb:checkbox{value=g_rand.enabled, notifier=function(v) g_rand.enabled=v end},
      vb:text{text="Randomize"},
    },
    vb:row{
      vb:slider{min=0,max=100,value=g_rand.fill_prob,width=210,
        notifier=function(v)
          g_rand.fill_prob = math.floor(v + 0.5)
          rand_prob_txt.text = g_rand.fill_prob .. "% Fill Probability"
        end},
      rand_prob_txt,
    },
    vb:space{height=2},
    vb:row{
      vb:checkbox{value=g_rand.whole_if_none, notifier=function(v) g_rand.whole_if_none=v end},
      vb:text{text="Randomize whole track if nothing is selected"},
    },
    vb:row{
      vb:checkbox{value=g_rand.minmax_only, notifier=function(v) g_rand.minmax_only=v end},
      vb:text{text="Randomize Min/Max Only"},
    },
    vb:row{
      vb:checkbox{value=g_rand.dont_overwrite, notifier=function(v) g_rand.dont_overwrite=v end},
      vb:text{text="Don't Overwrite Existing Data"},
    },
    vb:row{
      vb:checkbox{value=g_rand.lock_current_effects, notifier=function(v) g_rand.lock_current_effects=v end},
      vb:text{text="Lock all current effects"},
    },
    vb:row{
      vb:checkbox{value=g_rand.only_rows_with_effects, notifier=function(v) g_rand.only_rows_with_effects=v end},
      vb:text{text="Only Modify Rows With Effects"},
    },
    vb:row{
      vb:checkbox{value=g_rand.only_rows_with_notes, notifier=function(v) g_rand.only_rows_with_notes=v end},
      vb:text{text="Only Modify Rows With Notes"},
    },
    vb:space{height=2},
    vb:row{
      vb:text{text="Min", width=28},
      vb:slider{min=0,max=255,value=g_rand.min_val,width=190,
        notifier=function(v)
          g_rand.min_val = math.floor(v)
          if g_rand.min_val > g_rand.max_val then g_rand.min_val = g_rand.max_val end
          rand_min_txt.text = hex2(g_rand.min_val)
        end},
      rand_min_txt,
    },
    vb:row{
      vb:text{text="Max", width=28},
      vb:slider{min=0,max=255,value=g_rand.max_val,width=190,
        notifier=function(v)
          g_rand.max_val = math.floor(v)
          if g_rand.max_val < g_rand.min_val then g_rand.max_val = g_rand.min_val end
          rand_max_txt.text = hex2(g_rand.max_val)
        end},
      rand_max_txt,
    },
    vb:space{height=2},
    vb:button{text="Apply Randomize", width=140,
      notifier=function()
        if not g_rand.enabled then
          status("Randomizer is disabled.")
          return
        end
        randomize_effect_values{
          fill_prob = g_rand.fill_prob,
          whole_if_none = g_rand.whole_if_none,
          minmax_only = g_rand.minmax_only,
          dont_overwrite = g_rand.dont_overwrite,
          lock_current_effects = g_rand.lock_current_effects,
          only_rows_with_effects = g_rand.only_rows_with_effects,
          only_rows_with_notes = g_rand.only_rows_with_notes,
          min_val = g_rand.min_val,
          max_val = g_rand.max_val,
        }
      end},
  }

  -- ── Right panel tab switching ────────────────────────────
  local current_right = 1
  local panels = { col_vals_panel, qf_panel, randomizer_panel }
  local right_holder = vb:column {}
  right_holder:add_child(col_vals_panel)

  local sec_switch = vb:switch {
    items = {"Main","Quickies","Randomizer"},
    width = 310,
    notifier = function(idx)
      if idx == current_right then return end
      right_holder:remove_child(panels[current_right])
      current_right = idx
      right_holder:add_child(panels[idx])
    end,
  }

  return vb:row {
    margin=6, spacing=10,
    left_panel,
    vb:column{spacing=4, sec_switch, right_holder},
  }
end

-- ============================================================
-- SHOW / HIDE
-- ============================================================

local function show_tool()
  if g_dialog and g_dialog.visible then
    g_dialog:close(); g_dialog=nil; return
  end
  g_vol_val=64; g_pan_val=128; g_dly_val=0; g_fxa_val=0; g_sfxa_val=0
  g_anchor=1; g_collision=1; g_overflow=false; g_curve=1
  g_shift_amt=1; g_scale_val=10
  g_vol_lo=0; g_vol_hi=127; g_pan_lo=0; g_pan_hi=255
  g_fx_lo=0;  g_fx_hi=255
  g_rand.enabled = true
  g_rand.fill_prob = 50
  g_rand.whole_if_none = false
  g_rand.minmax_only = false
  g_rand.dont_overwrite = false
  g_rand.lock_current_effects = false
  g_rand.only_rows_with_effects = false
  g_rand.only_rows_with_notes = false
  g_rand.min_val = 0
  g_rand.max_val = 255
  write_mode=1
  g_dialog = renoise.app():show_custom_dialog("RN Commander", build_gui())
end

-- ============================================================
-- REGISTRATION
-- ============================================================

renoise.tool():add_menu_entry{name="Main Menu:Tools:RN Commander",invoke=show_tool}
renoise.tool():add_menu_entry{name="Pattern Editor:RN Commander",invoke=show_tool}
renoise.tool():add_keybinding{name="Global:Tools:Show RN Commander",invoke=show_tool}
renoise.tool():add_keybinding{name="Pattern Editor:Tools:Show RN Commander",invoke=show_tool}
