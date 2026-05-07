import SwiftUI
import UIKit

struct NativeSearchBarView: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    @Environment(\.focusReadTheme) private var theme

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UISearchBar {
        let searchBar = UISearchBar(frame: .zero)
        searchBar.delegate = context.coordinator
        searchBar.placeholder = placeholder
        searchBar.searchBarStyle = .minimal
        searchBar.autocapitalizationType = .none
        searchBar.autocorrectionType = .no
        searchBar.searchTextField.autocorrectionType = .no
        searchBar.searchTextField.autocapitalizationType = .none
        searchBar.searchTextField.spellCheckingType = .no
        searchBar.returnKeyType = .search

        return searchBar
    }

    func updateUIView(_ searchBar: UISearchBar, context: Context) {
        applyTheme(to: searchBar)

        if searchBar.text != text {
            searchBar.text = text
        }

        if searchBar.placeholder != placeholder {
            searchBar.placeholder = placeholder
        }

        if text.isEmpty && !searchBar.searchTextField.isFirstResponder {
            searchBar.setShowsCancelButton(false, animated: true)
        }
    }

    private func applyTheme(to searchBar: UISearchBar) {
        let palette = theme.palette
        let textField = searchBar.searchTextField

        searchBar.tintColor = palette.accent
        textField.backgroundColor = palette.controlBackground
        textField.textColor = palette.primaryText
        textField.tintColor = palette.accent
        textField.leftView?.tintColor = palette.secondaryText
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: palette.tertiaryText
            ]
        )
    }

    final class Coordinator: NSObject, UISearchBarDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
            searchBar.setShowsCancelButton(true, animated: true)
        }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            text = searchText
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            searchBar.resignFirstResponder()
        }

        func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
            text = ""
            searchBar.text = ""
            searchBar.setShowsCancelButton(false, animated: true)
            searchBar.resignFirstResponder()
        }
    }
}
