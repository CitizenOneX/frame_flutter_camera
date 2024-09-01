-- Frame to phone flags
IMAGE_MSG = 0x07

-- Phone to Frame flags
TAKE_PHOTO_MSG = 0x0d

-- every time byte data arrives just extract the data payload from the message
-- and save to the local app_data table so the main loop can pick it up and print it
function parse_take_photo(data)
	local quality_values = {10, 25, 50, 100}
	local metering_values = {'SPOT', 'CENTER_WEIGHTED', 'AVERAGE'}

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
parsers[TAKE_PHOTO_MSG] = parse_take_photo

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
				pcall(frame.bluetooth.send, string.char(IMAGE_MSG) .. string.char(string.byte(image_size, 1)) .. string.char(string.byte(image_size, 2)) .. data)
				bytes_sent = bytes_sent + string.len(data)
				frame.sleep(0.01)
			end
		else
			data = frame.camera.read_raw(frame.bluetooth.max_length() - 4)
			if (data == nil) then
				break
			else
				pcall(frame.bluetooth.send, string.char(IMAGE_MSG) .. data)
				bytes_sent = bytes_sent + string.len(data)
				frame.sleep(0.01)
			end
		end
	end
end

-- Main app loop
function app_loop()
    local last_batt_update = 0

	while true do
		-- process any raw items, if ready (parse into take_photo, then clear raw)
		local items_ready = process_raw_items()

		if items_ready > 0 then
			if (app_data[TAKE_PHOTO_MSG] ~= nil) then
				rc, err = pcall(camera_capture_and_send, app_data)

				if rc == false then
					print(err)
				end
			end
		end

        -- periodic battery level updates, 120s for a camera app
        last_batt_update = send_batt_if_elapsed(last_batt_update, 120)
		frame.sleep(0.1)
	end
end

-- run the main app loop
app_loop()