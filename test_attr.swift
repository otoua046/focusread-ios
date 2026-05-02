import SwiftUI

let text = "Hello"
var attr = AttributedString(text)
let strIndex = text.index(text.startIndex, offsetBy: 2)
if let attrIndex = AttributedString.Index(strIndex, within: attr) {
    let nextIndex = attr.index(afterCharacter: attrIndex)
    attr[attrIndex..<nextIndex].foregroundColor = .red
}
print(attr)
