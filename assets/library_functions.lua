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

	local chunkIndex = 0
	while true do
		local data = frame.camera.read(frame.bluetooth.max_length() - 4)
		if (data == nil) then
			pcall(frame.bluetooth.send, '\x08' .. chunkIndex)
			break
		else
			pcall(frame.bluetooth.send, '\x07' .. data)
			chunkIndex = chunkIndex + 1
			frame.sleep(0.015)
		end
	end
end
