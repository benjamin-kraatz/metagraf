#if os(macOS)
import MetagrafCore
import SwiftUI

/// First-run walkthrough for the permissions dictation depends on.
struct OnboardingWindow: View {
    let permissions: PermissionsCoordinator

    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            VStack(spacing: 10) {
                ForEach(PermissionsCoordinator.Permission.allCases) { permission in
                    PermissionRow(permission: permission, permissions: permissions)
                }
            }

            footer
        }
        .padding(28)
        .frame(width: 480)
        .onAppear {
            permissions.refresh()
            permissions.beginPolling()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tint)

            Text("Welcome to Metagraf")
                .font(.title2.weight(.semibold))

            Text(
                """
                Hold \(ModifierKey.rightOption.displayName) anywhere on your Mac, say what you \
                want written, and let go. Everything is transcribed on this device.
                """
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            if permissions.isReady {
                Label("You're all set", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else {
                Text("Metagraf can't dictate until both are granted.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                dismissWindow(id: MetagrafWindow.onboarding.rawValue)
            } label: {
                if permissions.isReady {
                    Text("Start dictating")
                } else {
                    Text("Continue anyway")
                }
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
        }
    }
}

private struct PermissionRow: View {
    let permission: PermissionsCoordinator.Permission
    let permissions: PermissionsCoordinator

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: permission.symbol)
                .font(.system(size: 16))
                .frame(width: 24, height: 24)
                .foregroundStyle(isGranted ? .green : .secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(permission.title)
                    .font(.headline)
                Text(permission.reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            action
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
    }

    private var isGranted: Bool {
        permissions.status(of: permission).isGranted
    }

    @ViewBuilder
    private var action: some View {
        if isGranted {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 18))
        } else {
            Button("Grant") {
                Task { await permissions.request(permission) }
                // Accessibility can only be granted in System Settings, so send
                // the user straight there rather than leaving them to find it.
                if permission == .accessibility {
                    permissions.openSettings(for: permission)
                }
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
    }
}
#endif
