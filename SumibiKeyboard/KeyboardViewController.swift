import SumibiCore
import UIKit

final class KeyboardViewController: UIInputViewController {
    private lazy var sharedSettings = SharedSettingsStore()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        _ = sharedSettings?.loadProviderConfiguration()
    }
}
