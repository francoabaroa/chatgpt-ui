class AudioPlaybackProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.audioBufferQueue = [];
    this.bufferPosition = 0;
    this.isPlaying = false;

    this.port.onmessage = (event) => {
      // Receive PCM16 audio data from the main thread
      const data = event.data;
      const int16Array = new Int16Array(data);
      // Convert Int16 PCM data to Float32
      const float32Array = new Float32Array(int16Array.length);
      for (let i = 0; i < int16Array.length; i++) {
        float32Array[i] = int16Array[i] / 0x8000;
      }
      this.audioBufferQueue.push(float32Array);
    };
  }

  process(inputs, outputs) {
    const output = outputs[0];
    const outputChannel = output[0]; // Assuming mono audio

    if (this.audioBufferQueue.length > 0) {
      let outputIndex = 0;
      while (outputIndex < outputChannel.length && this.audioBufferQueue.length > 0) {
        const currentBuffer = this.audioBufferQueue[0];
        const samplesToCopy = Math.min(
          currentBuffer.length - this.bufferPosition,
          outputChannel.length - outputIndex
        );
        outputChannel.set(
          currentBuffer.subarray(this.bufferPosition, this.bufferPosition + samplesToCopy),
          outputIndex
        );
        outputIndex += samplesToCopy;
        this.bufferPosition += samplesToCopy;

        // If we've reached the end of the current buffer, remove it and reset position
        if (this.bufferPosition >= currentBuffer.length) {
          this.audioBufferQueue.shift();
          this.bufferPosition = 0;
        }
      }

      // If there's still space in the output buffer, fill it with zeros (silence)
      if (outputIndex < outputChannel.length) {
        outputChannel.fill(0, outputIndex);
      }
    } else {
      // No audio data, output silence
      outputChannel.fill(0);
    }

    return true; // Keep the processor alive
  }
}

registerProcessor('audio-playback-processor', AudioPlaybackProcessor);