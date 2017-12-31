//
//  IOStream.swift
//  Edge
//
//  Created by Tyler Fleming Cloutier on 5/1/16.
//
//
import Foundation
import Dispatch
import StreamKit
import POSIX
// swiftlint:disable variable_name
#if os(Linux)
    import Glibc
    let empty_off_t = Glibc.off_t()
    let INT32_MAX = Glibc.INT32_MAX
#else
    import Darwin
    let empty_off_t = Darwin.off_t()
    let INT32_MAX = Darwin.INT32_MAX
#endif
// swiftlint:enable variable_name

public protocol IOStream: class {
    var channel: DispatchIO { get }
}

public protocol WritableIOStream: IOStream {
    func write(buffer: Data) -> Source<Int>
}

public extension WritableIOStream {

    func write(stream: Signal<Data>) -> Signal<Int> {
        return Signal { observer in
            var unwrittenByteCounts = [Int:Int]()
            var globalIndex = 0
            stream.onNext { data in
                let dataIndex = globalIndex
                globalIndex += 1

                let writeSource = self.write(buffer: data)
                writeSource.onNext { unwrittenBytes in
                    unwrittenByteCounts[dataIndex] = unwrittenBytes
                    observer.sendNext(unwrittenByteCounts.values.reduce(0, +))
                }
                writeSource.onCompleted {
                    unwrittenByteCounts[dataIndex] = nil
                }
                writeSource.onFailed { _ in
                    unwrittenByteCounts[dataIndex] = nil
                }
                writeSource.start()
            }
            return nil
        }
    }

    func write(buffer: Data) -> Source<Int> {
        return Source { observer in
            let writeChannel = DispatchIO(
                type: .stream,
                io: self.channel,
                queue: .main
            ) { error in
                if let systemError = SystemError(errorNumber: error) {
                    observer.sendFailed(systemError)
                }
            }

            // Allocate dispatch data
            // TODO: This does not seem right.
            // Work around crash for now.
            let dispatchData = buffer.withUnsafeBytes {
                return DispatchData(
                    bytes: UnsafeRawBufferPointer(start: $0, count: buffer.count)
                )
            }

            // Schedule write operation
            writeChannel.write(
                offset: empty_off_t,
                data: dispatchData,
                queue: .main
            ) { done, data, error in

                if let data = data {
                    // Report number of unwritten bytes
                    observer.sendNext(data.count)
                }

                if let systemError = SystemError(errorNumber: error) {
                    // If there was an error emit the error.
                    observer.sendFailed(systemError)
                }

                if done {
                    if error == 0 {
                        // If the done param is set and there is no error,
                        // all data has been written, emit writing end.
                        // DO NOT emit end otherwise!
                        observer.sendCompleted()
                    }

                    // Must be an unrecoverable error, close the channel.
                    // TODO: Maybe don't close if you want half-open channel
                    // NOTE: This will be done by onCompleted or onError
                    // dispatch_io_close(self.channel, 0)
                    writeChannel.close()
                }
            }

            return ActionDisposable {
                writeChannel.close()
            }
        }
    }
}

public protocol ReadableIOStream: IOStream {
    func read(minBytes: Int) -> Source<Data>
}

public extension ReadableIOStream {

    func read(minBytes: Int = 1) -> Source<Data> {

        return Source { observer in

            let readChannel = DispatchIO(type: .stream, io: self.channel, queue: .main) { error in
                if let systemError = SystemError(errorNumber: error) {
                    observer.sendFailed(systemError)
                }
            }

            readChannel.setLimit(lowWater: minBytes)
            readChannel.read(
                offset: empty_off_t,
                length: size_t(INT32_MAX),
                queue: .main
            ) { done, data, error in

                // Deliver data if it is non-empty
                if let data = data, !data.isEmpty {
                    data.enumerateBytes { (buffer, byteIndex, stop) in
                        observer.sendNext(Data(buffer))
                    }
                }

                if let systemError = SystemError(errorNumber: error) {
                    // If there was an error emit the error.
                    observer.sendFailed(systemError)
                }

                if done {
                     if error == 0 {
                        // If the done param is set and there is no error,
                        // all data has been read, emit end.
                        // DO NOT emit end otherwise!
                        observer.sendCompleted()
                    }

                    // It's done close the channel
                    // TODO: Maybe don't close if you want half-open channel
                    // NOTE: This will be done by onCompleted or onError
                    // dispatch_io_close(readChannel, 0)
                    readChannel.close()
                }
            }
            return ActionDisposable {
                readChannel.close()
            }
        }
    }
}
