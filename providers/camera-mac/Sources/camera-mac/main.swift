import Foundation

let stdoutQueue = DispatchQueue(label: "stdout")

func emit(_ obj: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: obj),
          let s = String(data: data, encoding: .utf8) else { return }
    stdoutQueue.sync { FileHandle.standardOutput.write(Data((s + "\n").utf8)) }
}

emit(["type": "hello", "protocol": 1,
      "provider": ["id": "camera-mac", "name": "Camera (macOS)", "version": "1.0.0"]])
