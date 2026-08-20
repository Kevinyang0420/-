import UIKit

// 最小可能的键盘扩展：一块紫色面板 + 一个按钮。
// 不录音、不联网、没有任何第三方依赖，viewDidLoad 里的活少到不可能超预算。
// 它是**对照组**：Transless 键盘弹不出来时，用它分辨是代码问题还是签装问题。

final class ProbeKeyboardViewController: UIInputViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.35, green: 0.2, blue: 0.6, alpha: 1)

        let label = UILabel()
        label.text = "探针键盘活着 ✓"
        label.textColor = .white
        label.font = .systemFont(ofSize: 22, weight: .bold)
        label.textAlignment = .center

        let btn = UIButton(type: .system)
        btn.setTitle("敲一个 OK", for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 18)
        btn.backgroundColor = UIColor(white: 1, alpha: 0.2)
        btn.layer.cornerRadius = 10
        btn.addTarget(self, action: #selector(typeOK), for: .touchUpInside)

        let globe = UIButton(type: .system)
        globe.setTitle("🌐", for: .normal)
        globe.addTarget(self, action: #selector(handleInputModeList(from:with:)),
                        for: .allTouchEvents)

        let stack = UIStackView(arrangedSubviews: [label, btn, globe])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            btn.widthAnchor.constraint(equalToConstant: 160),
            btn.heightAnchor.constraint(equalToConstant: 44),
            view.heightAnchor.constraint(equalToConstant: 220),
        ])
    }

    @objc private func typeOK() {
        textDocumentProxy.insertText("OK")
    }
}
