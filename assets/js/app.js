// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.

import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";
import hljs from "highlight.js";

function scrollToLastChatBubble() {
	let chatBubbles = document.querySelectorAll(".chat");
	let lastChatBubble = chatBubbles[chatBubbles.length - 1];
	if (lastChatBubble) {
		lastChatBubble.scrollIntoView({ behavior: "smooth", block: "start" });
	}
}

let Hooks = {};

Hooks.CopyMessage = {
	mounted() {
		this.el.addEventListener("click", () => {
			const content = this.el.getAttribute("data-content");
			if (content) {
				navigator.clipboard.writeText(content)
					.then(() => {
						this.el.innerText = "✅";
						setTimeout(() => {
							this.el.innerText = "📋";
						}, 2000);
					})
					.catch((err) => {
						console.error("Could not copy text: ", err);
						// Fallback mechanism for unsupported browsers
						let textarea = document.createElement("textarea");
						textarea.value = content;
						document.body.appendChild(textarea);
						textarea.select();
						try {
							document.execCommand("copy");
							this.el.innerText = "✅";
							setTimeout(() => {
								this.el.innerText = "📋";
							}, 2000);
						} catch (fallbackError) {
							console.error("Could not copy text via fallback:", fallbackError);
						}
						document.body.removeChild(textarea);
					});
			} else {
				console.warn("No content to copy.");
			}
		});
	},
};

Hooks.VoiceChat = {
	async mounted() {
		console.log("VoiceChat hook mounted");

		// Initialize audio contexts and playback variables
		this.audioContext = null; // For recording
		this.playbackAudioContext = new (window.AudioContext || window.webkitAudioContext)(); // For playback
		this.audioQueue = [];
		this.isPlaying = false;

		this.gainNode = this.playbackAudioContext.createGain();
		this.gainNode.connect(this.playbackAudioContext.destination);

		this.handleEvent("voice_chat_started", async () => {
			await this.startVoiceChat();
		});

		this.handleEvent("voice_chat_stopped", () => {
			this.stopVoiceChat();
		});

		// Handle incoming audio chunks
		this.handleEvent("audio_delta", (event) => {
			console.log("Received audio delta from server");
			this.enqueueAudio(event.delta);
		});

		this.handleServerEvents();
	},

	async startVoiceChat() {
		console.log("Starting voice chat");
		try {
			if (!this.audioContext || this.audioContext.state === 'closed') {
				await this.setupAudioWorklet();
			} else if (this.audioContext.state === 'suspended') {
				await this.audioContext.resume();
			}
		} catch (error) {
			console.error("Error starting voice chat:", error);
			// Optionally, notify the user about the error
			this.pushEvent("voice_chat_error", { message: "Failed to start voice chat" });
		}
	},

	stopVoiceChat() {
		if (this.audioContext && this.audioContext.state !== 'closed') {
			this.audioContext.close();
		}
		this.audioContext = null;
		if (this.stream) {
			this.stream.getTracks().forEach(track => track.stop());
			this.stream = null;
		}
		this.source = null;
		this.resamplerNode = null;
		console.log("Stopping voice chat");
		// Note: We're not closing playbackAudioContext here
	},

	async setupAudioWorklet() {
		this.audioContext = new AudioContext();

		// Load the audio worklet
		await this.audioContext.audioWorklet.addModule('/js/resampler-processor.js');

		// Create the worklet node
		this.resamplerNode = new AudioWorkletNode(this.audioContext, 'resampler-processor');

		// Handle messages from the processor
		this.resamplerNode.port.onmessage = (event) => {
			const float32Array = event.data;

			// Convert Float32Array to base64-encoded PCM16 data
			const base64Audio = this.base64EncodeAudio(float32Array);

			// Send audio data to the server
			this.pushEvent("send_audio_chunk", { audio: base64Audio });
		};

		// Send sample rate to the processor
		this.resamplerNode.port.postMessage({ sampleRate: this.audioContext.sampleRate });

		// Obtain audio input stream
		this.stream = await navigator.mediaDevices.getUserMedia({ audio: true });
		this.source = this.audioContext.createMediaStreamSource(this.stream);

		// Connect the nodes
		this.source.connect(this.resamplerNode);
		// We don't connect the resamplerNode to any destination since we're only processing audio
	},

	async resampleAudio(buffer, inputSampleRate, outputSampleRate) {
		const numberOfChannels = 1;
		const offlineContext = new OfflineAudioContext(numberOfChannels, buffer.length, inputSampleRate);
		const audioBuffer = offlineContext.createBuffer(numberOfChannels, buffer.length, inputSampleRate);
		audioBuffer.copyToChannel(buffer, 0);

		const bufferSource = offlineContext.createBufferSource();
		bufferSource.buffer = audioBuffer;
		bufferSource.connect(offlineContext.destination);
		bufferSource.start(0);

		const renderedBuffer = await offlineContext.startRendering();

		// Now, resample to the desired sample rate
		const resampledOfflineContext = new OfflineAudioContext(
			numberOfChannels,
			Math.ceil(renderedBuffer.duration * outputSampleRate),
			outputSampleRate
		);
		const resampledBufferSource = resampledOfflineContext.createBufferSource();
		resampledBufferSource.buffer = renderedBuffer;
		resampledBufferSource.connect(resampledOfflineContext.destination);
		resampledBufferSource.start(0);

		const resampledBuffer = await resampledOfflineContext.startRendering();

		return resampledBuffer.getChannelData(0);
	},

	floatTo16BitPCM(float32Array) {
		const buffer = new ArrayBuffer(float32Array.length * 2);
		const view = new DataView(buffer);
		let offset = 0;
		for (let i = 0; i < float32Array.length; i++, offset += 2) {
			let s = Math.max(-1, Math.min(1, float32Array[i]));
			view.setInt16(offset, s < 0 ? s * 0x8000 : s * 0x7fff, true);
		}
		return buffer;
	},

	base64EncodeAudio(float32Array) {
		const arrayBuffer = this.floatTo16BitPCM(float32Array);
		let binary = '';
		let bytes = new Uint8Array(arrayBuffer);
		const chunkSize = 0x8000; // 32KB chunk size
		for (let i = 0; i < bytes.length; i += chunkSize) {
			let chunk = bytes.subarray(i, i + chunkSize);
			binary += String.fromCharCode.apply(null, chunk);
		}
		return btoa(binary);
	},

	handleServerEvents() {
		this.handleEvent("error", (event) => {
			console.error("API error:", event.error);
			// Display error message to user
		});

		this.handleEvent("session_created", (event) => {
			console.log("Session created:", event.session);
		});

		this.handleEvent("session_updated", (event) => {
			console.log("Session updated:", event.session);
		});

		this.handleEvent("conversation_created", (event) => {
			console.log("Conversation created:", event.conversation);
		});

		this.handleEvent("input_audio_buffer_committed", (event) => {
			console.log("Audio buffer committed:", event);
		});

		this.handleEvent("input_audio_buffer_cleared", () => {
			console.log("Audio buffer cleared");
		});

		this.handleEvent("input_audio_buffer_speech_started", (event) => {
			console.log("Speech started:", event);
		});

		this.handleEvent("input_audio_buffer_speech_stopped", (event) => {
			console.log("Speech stopped:", event);
		});

		this.handleEvent("conversation_item_created", (event) => {
			console.log("Conversation item created:", event.item);
			this.updateChatUI(event.item);
		});

		this.handleEvent("conversation_item_input_audio_transcription_completed", (event) => {
			console.log("Audio transcription completed:", event);
		});

		this.handleEvent("conversation_item_input_audio_transcription_failed", (event) => {
			console.error("Audio transcription failed:", event.error);
		});

		this.handleEvent("conversation_item_truncated", (event) => {
			console.log("Conversation item truncated:", event);
		});

		this.handleEvent("conversation_item_deleted", (event) => {
			console.log("Conversation item deleted:", event);
		});

		this.handleEvent("response_created", (event) => {
			console.log("Response created:", event.response);
		});

		this.handleEvent("response_done", (event) => {
			console.log("Response done:", event.response);
			this.finishAssistantMessage();
		});

		this.handleEvent("response_output_item_added", (event) => {
			console.log("Output item added:", event.item);
		});

		this.handleEvent("response_output_item_done", (event) => {
			console.log("Output item done:", event.item);
		});

		this.handleEvent("response_content_part_added", (event) => {
			console.log("Content part added:", event.part);
		});

		this.handleEvent("response_content_part_done", (event) => {
			console.log("Content part done:", event.part);
		});

		this.handleEvent("response_text_delta", (event) => {
			console.log("Text delta received:", event.delta);
			this.appendToAssistantMessage(event.delta);
		});

		this.handleEvent("response_text_done", (event) => {
			console.log("Text done:", event.text);
		});

		this.handleEvent("response_audio_transcript_delta", (event) => {
			console.log("Audio transcript delta:", event.delta);
		});

		this.handleEvent("response_audio_transcript_done", (event) => {
			console.log("Audio transcript done:", event.transcript);
		});

		this.handleEvent("response_audio_delta", (event) => {
			console.log("Audio delta received");
			this.playAudio(event.delta);
		});

		this.handleEvent("response_audio_done", () => {
			console.log("Audio done");
		});

		this.handleEvent("response_function_call_arguments_delta", (event) => {
			console.log("Function call arguments delta:", event.delta);
		});

		this.handleEvent("response_function_call_arguments_done", (event) => {
			console.log("Function call arguments done:", event.arguments);
		});

		this.handleEvent("rate_limits_updated", (event) => {
			console.log("Rate limits updated:", event.rate_limits);
		});

		this.handleEvent("text_delta", (event) => {
			console.log("Text delta received:", event.delta);
			this.appendToAssistantMessage(event.delta);
		});

		this.handleEvent("audio_delta", ({ delta }) => {
			// Handle audio delta (e.g., play the audio)
		});

		this.handleEvent("audio_done", () => {
			// Handle audio completion
		});

		this.handleEvent("audio_transcript_done", () => {
			// Handle transcript completion
		});

		this.handleEvent("content_part_done", () => {
			// Handle content part completion
		});

		this.handleEvent("output_item_done", () => {
			// Handle output item completion
		});

		this.handleEvent("response_done", () => {
			// Handle overall response completion
		});

		this.handleEvent("rate_limits_updated", (data) => {
			// Handle rate limit updates
		});

		this.handleEvent("input_audio_buffer.speech_started", (event) => {
			console.log("Speech started", event);
		});

		this.handleEvent("input_audio_buffer.speech_stopped", (event) => {
			console.log("Speech stopped", event);
			this.commitAudio();
		});

		this.handleEvent("conversation.item.input_audio_transcription.completed", (event) => {
			console.log("Transcription completed", event);
		});

		this.handleEvent("response.text.delta", (event) => {
			console.log("Received text delta", event);
			this.appendToAssistantMessage(event.delta);
		});

		this.handleEvent("response.audio.delta", (event) => {
			console.log("Received audio delta", event);
			this.playAudio(event.delta);
		});

		this.handleEvent("response.done", (event) => {
			console.log("Response done", event);
			this.finishAssistantMessage();
		});
	},

	appendToAssistantMessage(delta) {
		let assistantMessage = document.getElementById('assistant-message');
		if (!assistantMessage) {
			assistantMessage = document.createElement('div');
			assistantMessage.id = 'assistant-message';
			assistantMessage.className = 'message assistant';
			document.getElementById('chat-window').appendChild(assistantMessage);
		}
		assistantMessage.textContent += delta;
		scrollToLastChatBubble();
	},

	finishAssistantMessage() {
		console.log("Assistant's message completed.");
		// Optionally mark the message as complete or perform any cleanup
		hljs.highlightAll();
	},

	enqueueAudio(base64Audio) {
		// Decode base64 audio data
		const audioData = atob(base64Audio);
		const byteArray = new Uint8Array(audioData.length);
		for (let i = 0; i < audioData.length; i++) {
			byteArray[i] = audioData.charCodeAt(i);
		}

		// Convert PCM16 data to Float32Array
		const bufferLength = byteArray.length / 2;
		const float32Array = new Float32Array(bufferLength);
		for (let i = 0; i < bufferLength; i++) {
			const index = i * 2;
			const sample = (byteArray[index + 1] << 8) | byteArray[index];
			// Convert from 16-bit PCM to float (-1 to 1)
			float32Array[i] = sample < 0x8000
				? sample / 0x8000
				: -((0xFFFF - sample + 1) / 0x8000);
		}

		// Create AudioBuffer and enqueue using playbackAudioContext
		const audioBuffer = this.playbackAudioContext.createBuffer(1, float32Array.length, 24000);
		audioBuffer.copyToChannel(float32Array, 0);

		this.audioQueue.push(audioBuffer);
		this.playAudioQueue();
	},

	playAudioQueue() {
		if (this.isPlaying || this.audioQueue.length === 0) {
			return;
		}

		this.isPlaying = true;
		const audioBuffer = this.audioQueue.shift();

		const source = this.playbackAudioContext.createBufferSource();
		source.buffer = audioBuffer;
		source.connect(this.gainNode);
		source.start();

		source.onended = () => {
			this.isPlaying = false;
			this.playAudioQueue();
		};
	},

	setVolume(volume) {
		if (this.gainNode) {
			this.gainNode.gain.setValueAtTime(volume, this.playbackAudioContext.currentTime);
		}
	},

	createWavFile(byteArray) {
		const buffer = new ArrayBuffer(44 + byteArray.length);
		const view = new DataView(buffer);

		/* RIFF identifier */
		this.writeString(view, 0, 'RIFF');
		/* file length */
		view.setUint32(4, 36 + byteArray.length, true);
		/* RIFF type */
		this.writeString(view, 8, 'WAVE');
		/* format chunk identifier */
		this.writeString(view, 12, 'fmt ');
		/* format chunk length */
		view.setUint32(16, 16, true);
		/* sample format (raw) */
		view.setUint16(20, 1, true);
		/* channel count */
		view.setUint16(22, 1, true);
		/* sample rate */
		view.setUint32(24, 24000, true);
		/* byte rate (sample rate * block align) */
		view.setUint32(28, 24000 * 2, true);
		/* block align (channel count * bytes per sample) */
		view.setUint16(32, 2, true);
		/* bits per sample */
		view.setUint16(34, 16, true);
		/* data chunk identifier */
		this.writeString(view, 36, 'data');
		/* data chunk length */
		view.setUint32(40, byteArray.length, true);

		// Write PCM samples
		for (let i = 0; i < byteArray.length; i++) {
			view.setUint8(44 + i, byteArray[i]);
		}

		return buffer;
	},

	writeString(view, offset, string) {
		for (let i = 0; i < string.length; i++) {
			view.setUint8(offset + i, string.charCodeAt(i));
		}
	},

	updateChatUI(item) {
		const chatWindow = document.getElementById('chat-window');
		if (!chatWindow) {
			console.error('Chat window element not found');
			return;
		}
		const messageElement = document.createElement('div');
		messageElement.className = `message ${item.role}`;
		messageElement.textContent = item.content[0].text;
		chatWindow.appendChild(messageElement);
		scrollToLastChatBubble();
	},

	commitAudio() {
		this.pushEvent('commit_audio', {});
	},

	destroyed() {
		if (this.audioContext && this.audioContext.state !== 'closed') {
			this.audioContext.close();
		}
		if (this.playbackAudioContext && this.playbackAudioContext.state !== 'closed') {
			this.playbackAudioContext.close();
		}
	},

	pauseAudio() {
		if (this.playbackAudioContext.state === 'running') {
			this.playbackAudioContext.suspend();
		}
	},

	resumeAudio() {
		if (this.playbackAudioContext.state === 'suspended') {
			this.playbackAudioContext.resume();
		}
	},

	setupAudioVisualizer() {
		this.analyser = this.playbackAudioContext.createAnalyser();
		this.analyser.fftSize = 256;
		this.gainNode.connect(this.analyser);

		const bufferLength = this.analyser.frequencyBinCount;
		const dataArray = new Uint8Array(bufferLength);

		const canvas = document.getElementById('visualizer');
		const canvasCtx = canvas.getContext('2d');

		const draw = () => {
			requestAnimationFrame(draw);
			this.analyser.getByteFrequencyData(dataArray);

			canvasCtx.fillStyle = 'rgb(0, 0, 0)';
			canvasCtx.fillRect(0, 0, canvas.width, canvas.height);

			const barWidth = (canvas.width / bufferLength) * 2.5;
			let barHeight;
			let x = 0;

			for (let i = 0; i < bufferLength; i++) {
				barHeight = dataArray[i] / 2;
				canvasCtx.fillStyle = `rgb(${barHeight + 100},50,50)`;
				canvasCtx.fillRect(x, canvas.height - barHeight / 2, barWidth, barHeight);
				x += barWidth + 1;
			}
		};

		draw();
	},
};

let csrfToken = document
	.querySelector("meta[name='csrf-token']")
	.getAttribute("content");

let liveSocket = new LiveSocket("/live", Socket, {
	params: { _csrf_token: csrfToken },
	hooks: Hooks,
	socket: new Socket("/socket", { params: { token: window.userToken } })
});

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

// connect if there are any LiveViews on the page
liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation:
window.liveSocket = liveSocket;

window.addEventListener(`phx:newmessage`, (e) => {
	console.log("new message arrived");
	hljs.highlightAll();
	scrollToLastChatBubble();
});

// Handle the open_drive_search_modal event
window.addEventListener("phx:open_drive_search_modal", (e) => {
	console.log("Opening Google Drive search modal");
	// Implement the logic to open your Google Drive search modal here
});

// Handle click events
window.addEventListener("phx:click", (e) => {
	if (e.target.getAttribute("phx-click") === "open_drive_search") {
		console.log("Search Google Drive button clicked");
	}
});

// Handle LiveView updates
window.addEventListener("phx:update", (e) => {
	console.log("LiveView updated", e.detail);
});

// Handle voice chat start event
window.addEventListener("phx:start_voice_chat", (e) => {
	console.log("Starting voice chat");
	// You might want to add some UI indication that voice chat is active
});