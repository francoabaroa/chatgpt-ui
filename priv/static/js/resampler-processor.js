class ResamplerProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.targetSampleRate = 24000;
    this.buffer = [];
    this.sampleRatio = 1;

    this.port.onmessage = (event) => {
      if (event.data.sampleRate) {
        this.sampleRatio = event.data.sampleRate / this.targetSampleRate;
      }
    };
  }

  process(inputs, outputs, parameters) {
    const input = inputs[0];
    if (input.length > 0) {
      const inputData = input[0];

      // Accumulate samples
      this.buffer = this.buffer.concat(Array.from(inputData));

      // Check if we have enough samples to resample
      if (this.buffer.length >= this.sampleRatio * 128) {
        const resampledData = this.resample(this.buffer);
        this.port.postMessage(resampledData);
        this.buffer = [];
      }
    }
    return true;
  }

  resample(inputBuffer) {
    const outputLength = Math.floor(inputBuffer.length / this.sampleRatio);
    const output = new Float32Array(outputLength);

    for (let i = 0; i < outputLength; i++) {
      const inputIndex = i * this.sampleRatio;
      const index = Math.floor(inputIndex);
      const fraction = inputIndex - index;

      if (index + 1 < inputBuffer.length) {
        output[i] = inputBuffer[index] * (1 - fraction) + inputBuffer[index + 1] * fraction;
      } else {
        output[i] = inputBuffer[index];
      }
    }

    return output;
  }
}

registerProcessor('resampler-processor', ResamplerProcessor);