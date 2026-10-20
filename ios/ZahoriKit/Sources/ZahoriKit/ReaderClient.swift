import Foundation
import ZahoriCore

/// Reader credentials ("Nº de carné" + password). Stored by the app in the Keychain.
public struct ReaderCredentials: Codable, Equatable, Sendable {
    public var card: String
    public var password: String

    public init(card: String, password: String) {
        self.card = card
        self.password = password
    }
}

public enum ReaderError: Error, Equatable, Sendable {
    /// The OPAC answered the login with the login form again.
    case invalidCredentials
    /// Network failure, handshake failure or markup we do not recognise.
    case catalogUnavailable(reason: String)
}

/// Logs into the reader area and reads the current loans.
/// Flow: OPAC session → POST `abnopid` (ACC=201) → "Mi biblioteca" (ACC=210) → parse → "Desconectar" (ACC=202).
public struct ReaderClient: Sendable {
    public var opac: OPACClient
    public var parser: ReaderParser

    public init(opac: OPACClient = OPACClient(), parser: ReaderParser = ReaderParser()) {
        self.opac = opac
        self.parser = parser
    }

    public func fetchLoans(_ credentials: ReaderCredentials) async -> Result<[Loan], ReaderError> {
        let card = credentials.card.trimmingCharacters(in: .whitespaces)
        guard !card.isEmpty, !credentials.password.isEmpty else { return .failure(.invalidCredentials) }

        let session: OPACClient.Session
        do {
            session = try await opac.openSession()
        } catch {
            return .failure(.catalogUnavailable(reason: String(localized: "No se pudo conectar con el catálogo de bibliotecas: \(OPACClient.describe(error))", bundle: .module)))
        }
        let http = session.http
        let formPage = session.formPage

        guard let form = parser.loginForm(formPage.text),
              let actionURL = URL(string: form.action, relativeTo: formPage.url)?.absoluteURL else {
            return .failure(.catalogUnavailable(reason: String(localized: "No se encontró el formulario de acceso del lector", bundle: .module)))
        }

        // 1. Log in
        let afterLogin: HTTPResponse
        do {
            afterLogin = try await http.postForm(actionURL, fields: form.hiddenFields
                + [(form.cardField, card), (form.passwordField, credentials.password)])
            guard afterLogin.status == 200 else { throw NetworkError.http(status: afterLogin.status) }
        } catch {
            return .failure(.catalogUnavailable(reason: String(localized: "Error al identificarse en el catálogo: \(OPACClient.describe(error))", bundle: .module)))
        }
        let page = afterLogin.text
        guard parser.isLoggedIn(page) else {
            return .failure(parser.hasPasswordField(page)
                ? .invalidCredentials
                : .catalogUnavailable(reason: String(localized: "Respuesta de acceso no reconocida", bundle: .module)))
        }

        // 2. Mi biblioteca
        let libraryURL = parser.myLibraryLink(page).flatMap { URL(string: $0, relativeTo: afterLogin.url)?.absoluteURL }
            ?? URL(string: "?ACC=210", relativeTo: afterLogin.url)!.absoluteURL
        let result: Result<[Loan], ReaderError>
        do {
            let library = try await http.get(libraryURL)
            guard library.status == 200 else { throw NetworkError.http(status: library.status) }
            switch parser.parseLoans(library.text, baseURL: library.url) {
            case let .loans(loans): result = .success(loans)
            case .unrecognized:
                result = .failure(.catalogUnavailable(reason: String(localized: "La página de préstamos no tiene el formato esperado", bundle: .module)))
            }
        } catch {
            result = .failure(.catalogUnavailable(reason: String(localized: "Error al cargar tus préstamos: \(OPACClient.describe(error))", bundle: .module)))
        }

        // 3. Close the reader session (best effort, errors ignored).
        if let logout = parser.logoutLink(page).flatMap({ URL(string: $0, relativeTo: afterLogin.url)?.absoluteURL }) {
            _ = try? await http.get(logout)
        }
        return result
    }
}
