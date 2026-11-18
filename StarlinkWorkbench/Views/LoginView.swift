import SwiftUI

/// 登录页（STRATUM 极简版式，对齐原生内部版）：
/// 蓝色品牌标题 + 墨线输入框 + 墨块→强调色主按钮 + 底部版本号。
/// 管理员邮箱验证码流程自动转网页登录（会话仍隔离于本应用）。
struct LoginView: View {
    @EnvironmentObject var model: AppModel
    @State private var username = UserDefaults.standard.string(forKey: Constants.rememberedUsernameKey) ?? ""
    @State private var password = KeychainStore.load() ?? ""
    @State private var remember = KeychainStore.load() != nil
    @State private var showPassword = false

    var body: some View {
        ZStack {
            Color.wxBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer(minLength: 46)

                // 品牌标题（对齐原生内部版：蓝色大字 + 副题）
                VStack(spacing: 10) {
                    Text("星链")
                        .font(Strat.mono(44, weight: .heavy))
                        .tracking(2)
                        .foregroundColor(Color(hex: 0x0A7CFF))
                    Text("内部版")
                        .font(.system(size: 15))
                        .foregroundColor(Color.wxSecondaryText)
                }
                .padding(.bottom, 44)

                // 表单
                VStack(spacing: 16) {
                    TextField("账号", text: $username)
                        .font(.system(size: 17))
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .padding(.horizontal, 14)
                        .frame(height: 52)
                        .background(Color.wxCell)
                        .cornerRadius(Strat.corner)
                        .overlay(
                            RoundedRectangle(cornerRadius: Strat.corner)
                                .strokeBorder(Color.inkLine, lineWidth: 1)
                        )

                    HStack(spacing: 12) {
                        HStack {
                            SecureField("密码", text: $password)
                                .font(.system(size: 17))
                                .textContentType(.password)
                                .submitLabel(.go)
                                .onSubmit(submit)
                            Button(action: { showPassword.toggle() }) {
                                Image(systemName: showPassword ? "eye" : "eye.slash")
                                    .font(.system(size: 15))
                                    .foregroundColor(Color.inkLine)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 52)
                        .background(Color.wxCell)
                        .cornerRadius(Strat.corner)
                        .overlay(
                            RoundedRectangle(cornerRadius: Strat.corner)
                                .strokeBorder(Color.inkLine, lineWidth: 1)
                        )
                    }

                    HStack(spacing: 9) {
                        Toggle(isOn: $remember) { EmptyView() }
                            .toggleStyle(SwitchToggleStyle(tint: Color.wxGreen))
                            .labelsHidden()
                            .fixedSize()
                        Text("记住密码")
                            .font(.system(size: 13))
                            .foregroundColor(Color.wxSecondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)

                    Button(action: submit) {
                        Group {
                            if model.loginState == .loading {
                                ProgressView().tint(.white)
                            } else {
                                Text("登录")
                                    .font(Strat.mono(17, weight: .semibold))
                                    .tracking(6)
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: Strat.corner)
                                .fill(canSubmit ? Color.accent : Color(hex: 0xB8B8BE))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)

                    if case .error(let message) = model.loginState {
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundColor(Color.wxDanger)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 24)

                // 演示入口（无网回归用）
                HStack(spacing: 8) {
                    Text("演示")
                        .font(.system(size: 11))
                        .foregroundColor(Color.wxTertiaryText)
                    Button("登录失败") { model.demoLoginFail() }
                        .font(.system(size: 12))
                        .foregroundColor(Color.wxSecondaryText)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(Color.wxCell)
                        .cornerRadius(Strat.corner)
                        .overlay(RoundedRectangle(cornerRadius: Strat.corner).strokeBorder(Color.inkLine, lineWidth: 1))
                    Button("登录通过") { model.demoLoginOk() }
                        .font(.system(size: 12))
                        .foregroundColor(Color.wxSecondaryText)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(Color.wxCell)
                        .cornerRadius(Strat.corner)
                        .overlay(RoundedRectangle(cornerRadius: Strat.corner).strokeBorder(Color.inkLine, lineWidth: 1))
                }

                Spacer(minLength: 18)

                Text("v1.6.1 (8)")
                    .font(.system(size: 12))
                    .foregroundColor(Color.wxTertiaryText)
                    .padding(.bottom, 16)
            }
        }
        .navigationBarHidden(true)
    }

    private var canSubmit: Bool {
        if case .loading = model.loginState { return false }
        return !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        model.login(username: username.trimmingCharacters(in: .whitespaces),
                    password: password,
                    remember: remember)
    }
}
