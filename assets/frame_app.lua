-- we store the data from the host quickly from the data handler interrupt
-- and wait for the main loop to pick it up for processing/drawing
-- app_data contains all camera settings settable from the UI
-- quality, exposure, metering mode, ...
local app_data = { quality = 50, auto_exp_gain_times = 0, metering_mode = "SPOT", exposure = 0, shutter_kp = 0.1, shutter_limit = 6000, gain_kp = 1.0, gain_limit = 248.0}
local take_photo = false
local quality_values = {10, 25, 50, 100}
local metering_values = {'SPOT', 'CENTER_WEIGHTED', 'AVERAGE'}

-- Frame to phone flags
BATTERY_LEVEL_FLAG = 0x0c
IMAGE_CHUNK_FLAG = 0x07

-- Phone to Frame flags
TAKE_PHOTO_FLAG = 0x0d

-- every time byte data arrives just extract the data payload from the message
-- and save to the local app_data table so the main loop can pick it up and print it
function data_handler(data)
    if string.byte(data, 1) == TAKE_PHOTO_FLAG then
        -- quality and metering mode are indices into arrays of values (0-based phoneside; 1-based in Lua)
        -- exposure maps from 0..255 to -2.0..+2.0
        app_data.quality = quality_values[string.byte(data, 2) + 1]
        app_data.auto_exp_gain_times = string.byte(data, 3)
        app_data.metering_mode = metering_values[string.byte(data, 4) + 1]
        app_data.exposure = (string.byte(data, 5) - 128) / 64.0
        app_data.shutter_kp = string.byte(data, 6) / 10.0
        app_data.shutter_limit = string.byte(data, 7) << 8 | string.byte(data, 8)
        app_data.gain_kp = string.byte(data, 9) / 10.0
        app_data.gain_limit = string.byte(data, 10)
		take_photo = true
    end
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

	-- TODO is it really true we need to pause here? earlier tests showed we didn't but now it seems we do(!)
	-- TODO keep checking register 0x21 every few ms until it gives the same result twice in a row?
	frame.sleep(0.25) -- 0.1? 0.2? 0.5? Quality dependent?
	image_size = frame.fpga.read(0x21, 2)
	print('Read size from reg 0x21:' .. tostring(string.byte(image_size, 1) << 8 | string.byte(image_size, 2)))
	frame.sleep(0.25) -- 0.1? 0.2? 0.5? Quality dependent?
	image_size = frame.fpga.read(0x21, 2)
	print('Read size from reg 0x21:' .. tostring(string.byte(image_size, 1) << 8 | string.byte(image_size, 2)))
	frame.sleep(0.25) -- 0.1? 0.2? 0.5? Quality dependent?
	image_size = frame.fpga.read(0x21, 2)
	print('Read size from reg 0x21:' .. tostring(string.byte(image_size, 1) << 8 | string.byte(image_size, 2)))
	frame.sleep(0.25) -- 0.1? 0.2? 0.5? Quality dependent?
	image_size = frame.fpga.read(0x21, 2)
	print('Read size from reg 0x21:' .. tostring(string.byte(image_size, 1) << 8 | string.byte(image_size, 2)))

	frame.sleep(2.0) -- 0.1? 0.2? 0.5? Quality dependent?

	local data = ''

	while true do
		if first_chunk then
			first_chunk = false
			data = frame.camera.read_raw(frame.bluetooth.max_length() - 6)
			print('first data read: ' .. tostring(string.len(data)))
			if (data ~= nil) then
				pcall(frame.bluetooth.send, string.char(IMAGE_CHUNK_FLAG) .. string.char(string.byte(image_size, 1)) .. string.char(string.byte(image_size, 2)) .. data)
				bytes_sent = bytes_sent + string.len(data)
				frame.sleep(0.02)
			end
		else
			data = frame.camera.read_raw(frame.bluetooth.max_length() - 4)
			if (data == nil) then
				break
			else
				print('next data read: ' .. tostring(string.len(data)))
				pcall(frame.bluetooth.send, string.char(IMAGE_CHUNK_FLAG) .. data)
				bytes_sent = bytes_sent + string.len(data)
				frame.sleep(0.02)
			end
		end
		print('total bytes sent: ' .. tostring(bytes_sent))

		-- TODO remove after checking (bytes left to read?)
		frame.sleep(0.25) -- 0.1? 0.2? 0.5? Quality dependent?
		local fpga_remaining = frame.fpga.read(0x21, 2)
		print('FPGA remaining from reg 0x21:' .. tostring(string.byte(fpga_remaining, 1) << 8 | string.byte(fpga_remaining, 2)))
	end
	print('final total bytes sent: ' .. tostring(bytes_sent))
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
		if take_photo then
			take_photo = false

			rc, err = pcall(camera_capture_and_send, app_data)
			if rc == false then
				print(err)
			end
		end

        -- periodic battery level updates, 12s for a camera app
        last_batt_update = send_batt_if_elapsed(last_batt_update, 120)
		frame.sleep(0.1)
	end
end

-- register the handler as a callback for all data sent from the host
frame.bluetooth.receive_callback(data_handler)

-- run the main app loop
app_loop()