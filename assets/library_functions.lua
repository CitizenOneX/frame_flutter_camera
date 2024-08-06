function cameraCaptureAndSend(quality,autoExpTimeDelay,meteringType)
	local last_autoexp_time = 0
	local state = 'EXPOSING'
	local state_time = frame.time.utc()
	local chunkIndex = 0
	if autoExpTimeDelay == nil then
			state = 'CAPTURE'
	end

	while true do
		if state == 'EXPOSING' then
				if frame.time.utc() - last_autoexp_time > 0.1 then
						frame.camera.auto { metering = meteringType }
						last_autoexp_time = frame.time.utc()
				end
				if frame.time.utc() > state_time + autoExpTimeDelay then
						state = 'CAPTURE'
				end
		elseif state == 'CAPTURE' then
				frame.camera.capture { quality_factor = quality }
				state_time = frame.time.utc()
				state = 'WAIT'
		elseif state == 'WAIT' then
				if frame.time.utc() > state_time + 0.5 then
					state = 'SEND'
				end
		elseif state == 'SEND' then
				local i = frame.camera.read(frame.bluetooth.max_length() - 4)
				if (i == nil) then
						state = 'DONE'
				else
					while true do
							if pcall(frame.bluetooth.send, '\x07' .. i) then
									break
							end
							frame.sleep(0.01)
					end
					chunkIndex = chunkIndex + 1
				end
		elseif state == 'DONE' then
			while true do
				if pcall(frame.bluetooth.send, '\x08' .. chunkIndex) then
					break
				end
			end
			break
		end
	end
end
