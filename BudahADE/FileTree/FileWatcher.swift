import Foundation

final class FileWatcher: ObservableObject {

    let path: String
    var onChange: () -> Void

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var debounceWork: DispatchWorkItem?

    init(path: String, onChange: @escaping () -> Void = {}) {
        self.path = path
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    // MARK: - Public

    func start() {
        stop()

        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: .global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            self?.scheduleUpdate()
        }

        source.setCancelHandler { [weak self] in
            guard let self = self, self.fileDescriptor >= 0 else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
        }

        source.resume()
        self.source = source
    }

    func stop() {
        debounceWork?.cancel()
        debounceWork = nil

        if let source = source {
            source.cancel()
            self.source = nil
        } else if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    // MARK: - Private

    private func scheduleUpdate() {
        debounceWork?.cancel()

        let work = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                self?.onChange()
            }
        }

        debounceWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + .milliseconds(100),
            execute: work
        )
    }
}
