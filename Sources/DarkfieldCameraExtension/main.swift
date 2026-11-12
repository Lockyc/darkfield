import CoreMediaIO
import Foundation

let provider = Provider()
CMIOExtensionProvider.startService(provider: provider.provider)
CFRunLoopRun()
