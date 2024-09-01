-- we store the data from the host quickly from the data handler interrupt
-- and wait for the main loop to pick it up for processing/drawing
-- app_data contains all camera settings settable from the UI
-- quality, exposure, metering mode, ...
local quality_values = {10, 25, 50, 100}
local metering_values = {'SPOT', 'CENTER_WEIGHTED', 'AVERAGE'}

-- Frame to phone flags
BATTERY_LEVEL_FLAG = 0x0c
IMAGE_CHUNK_FLAG = 0x07

-- Phone to Frame flags
TAKE_PHOTO_MSG = 0x0d

-- accumulates chunks of input message into this table
local app_data_accum = {}
-- after table.concat, this table contains the message code mapped to the full input message payload
local app_data_block = {}
-- contains typed objects representing full messages
local app_data = {}

-- Data Handler: called when data arrives, must execute quickly.
-- Update the app_data_accum item based on the contents of the current packet
-- The first byte of the packet indicates the message type, and the item's key
-- If the key is not present, initialise a new app data item
-- Accumulate chunks of data of the specified type, for later processing
-- TODO add reliability features (packet acknowledgement or dropped packet retransmission requests, message and packet sequence numbers)
function update_app_data_accum(data)
    local msg_flag = string.byte(data, 1)
    local item = app_data_accum[msg_flag]
    if item == nil or next(item) == nil then
        item = { chunk_table = {}, num_chunks = 0, size = 0, recv_bytes = 0 }
        app_data_accum[msg_flag] = item
    end

    if item.num_chunks == 0 then
        -- first chunk of new data contains size (Uint16)
        item.size = string.byte(data, 2) << 8 | string.byte(data, 3)
        item.chunk_table[1] = string.sub(data, 4)
        item.num_chunks = 1
        item.recv_bytes = string.len(data) - 3

        if item.recv_bytes == item.size then
            app_data_block[msg_flag] = item.chunk_table[1]
            item.size = 0
            item.recv_bytes = 0
            item.num_chunks = 0
            item.chunk_table[1] = nil
            app_data_accum[msg_flag] = item
        end
    else
        item.chunk_table[item.num_chunks + 1] = string.sub(data, 2)
        item.num_chunks = item.num_chunks + 1
        item.recv_bytes = item.recv_bytes + string.len(data) - 1

        -- if all bytes are received, concat and move message to block
        -- but don't parse yet
        if item.recv_bytes == item.size then
            app_data_block[msg_flag] = table.concat(item.chunk_table)

            for k, v in pairs(item.chunk_table) do item.chunk_table[k] = nil end
            item.size = 0
            item.recv_bytes = 0
            item.num_chunks = 0
            app_data_accum[msg_flag] = item
        end
    end
end

-- register the handler as a callback for all data sent from the host
frame.bluetooth.receive_callback(update_app_data_accum)

-- every time byte data arrives just extract the data payload from the message
-- and save to the local app_data table so the main loop can pick it up and print it
function parse_take_photo(data)
	local take_photo = {}
	-- quality and metering mode are indices into arrays of values (0-based phoneside; 1-based in Lua)
	-- exposure maps from 0..255 to -2.0..+2.0
	take_photo.quality = quality_values[string.byte(data, 2) + 1]
	take_photo.auto_exp_gain_times = string.byte(data, 3)
	take_photo.metering_mode = metering_values[string.byte(data, 4) + 1]
	take_photo.exposure = (string.byte(data, 5) - 128) / 64.0
	take_photo.shutter_kp = string.byte(data, 6) / 10.0
	take_photo.shutter_limit = string.byte(data, 7) << 8 | string.byte(data, 8)
	take_photo.gain_kp = string.byte(data, 9) / 10.0
	take_photo.gain_limit = string.byte(data, 10)
	return take_photo
end

-- register the respective message parsers
local parsers = {}
parsers[TAKE_PHOTO_FLAG] = parse_take_photo

-- Works through app_data_block and if any items are ready, run the corresponding parser
function process_raw_items()
    local processed = 0

    for flag, block in pairs(app_data_block) do
        -- parse the app_data_block item into an app_data item
        app_data[flag] = parsers[flag](block)

        -- then clear out the raw data
        app_data_block[flag] = nil

        processed = processed + 1
    end

    return processed
end

function camera_capture_and_send(args)
	quality = args.quality or 50
	auto_exp_gain_times = args.auto_exp_gain_times or 0
	metering_mode = args.metering_mode or 'SPOT'
	exposure = args.exposure or 0
	shutter_kp = args.shutter_kp or 0.1
	shutter_limit = args.shutter_limit or 6000
	gain_kp = args.gain_kp or 1.0
	gain_limit = args.gain_limit or 248.0

	for run=1,auto_exp_gain_times,1 do
		frame.camera.auto { metering = metering_mode, exposure = exposure, shutter_kp = shutter_kp, shutter_limit = shutter_limit, gain_kp = gain_kp, gain_limit = gain_limit }
		frame.sleep(0.1)
	end

	frame.camera.capture { quality_factor = quality }

	local first_chunk = true
	local image_size = 0
	local bytes_sent = 0

	-- keep polling the available bytes until it stabilizes for 0.1s
	local image_size = 0
	local prev_size = -1
	repeat
		frame.sleep(0.1)
		prev_size = image_size
		image_size = frame.fpga.read(0x21, 2)
	until (image_size == prev_size and image_size ~= 0)

	local data = ''

	while true do
		if first_chunk then
			first_chunk = false
			data = frame.camera.read_raw(frame.bluetooth.max_length() - 6)
			if (data ~= nil) then
				pcall(frame.bluetooth.send, string.char(IMAGE_CHUNK_FLAG) .. string.char(string.byte(image_size, 1)) .. string.char(string.byte(image_size, 2)) .. data)
				bytes_sent = bytes_sent + string.len(data)
				frame.sleep(0.01)
			end
		else
			data = frame.camera.read_raw(frame.bluetooth.max_length() - 4)
			if (data == nil) then
				break
			else
				pcall(frame.bluetooth.send, string.char(IMAGE_CHUNK_FLAG) .. data)
				bytes_sent = bytes_sent + string.len(data)
				frame.sleep(0.01)
			end
		end
	end
end

function send_batt_if_elapsed(prev, interval)
    local t = frame.time.utc()
    if ((prev == 0) or ((t - prev) > interval)) then
        pcall(frame.bluetooth.send, string.char(BATTERY_LEVEL_FLAG) .. string.char(math.floor(frame.battery_level())))
        return t
    else
        return prev
    end
end

-- Main app loop
function app_loop()
    local last_batt_update = 0

	while true do
		-- process any raw items, if ready (parse into take_photo, then clear raw)
		local items_ready = process_raw_items()

		-- TODO tune sleep durations to optimise for data handler and processing
		frame.sleep(0.005)

		if items_ready > 0 then
			if (app_data[TAKE_PHOTO_FLAG] ~= nil) then
				rc, err = pcall(camera_capture_and_send, app_data)

				if rc == false then
					print(err)
				end
			end
		end

        -- periodic battery level updates, 12s for a camera app
        last_batt_update = send_batt_if_elapsed(last_batt_update, 120)
		frame.sleep(0.1)
	end
end

-- run the main app loop
app_loop()