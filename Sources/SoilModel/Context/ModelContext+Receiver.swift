import Soil

extension ModelContext {

    /**
     A SOIL receiver which stores incoming data and notifies the models of the context about the changes.

     Use the receiver for data from other SOIL components, e.g. to keep models up to date with a remote storage:

     ```swift
     let remote = await RemoteObservableStorage(connection: connection)
     await remote.setReceiver(context.receiver).wait()
     await remote.include(context.root, depth: nil).wait()
     ```
     */
    public nonisolated var receiver: some Receiver {
        ModelContextReceiver(storage: storage, context: self)
    }
}

/**
 A receiver that writes data to the storage of a context, and notifies the context afterwards.
 */
struct ModelContextReceiver: Receiver {

    let storage: any ModelStorage

    weak let context: ModelContext?

    @discardableResult
    func accept(_ tree: any SampleTree, for path: Path) -> any Request {
        let request = storage.accept(tree, for: path)
        return AsyncRequest { [context] in
            await request.wait()
            await context?.storageDidChange(tree, at: path)
        }
    }
}
