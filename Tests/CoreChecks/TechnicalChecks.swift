import Foundation
import PDFKit
import ConversionCore

func checkTechnicalRoutes() async throws {
    let fm = FileManager.default
    let folder = fm.temporaryDirectory.appendingPathComponent("technical-check-\(UUID())")
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: folder) }
    let queue = ConversionQueue(registry: .local())
    if TectonicEngine().availability == .ready {
        let source = folder.appendingPathComponent("Local project.tex")
        try """
        \\documentclass[11pt]{article}
        \\begin{document}
        See Section \\ref{sec:example}.
        \\input{chapter}
        \\end{document}
        """.write(to: source, atomically: true, encoding: .utf8)
        try """
        \\section{Offline chapter}\\label{sec:example}
        Equation $x^2+y^2=z^2$.
        """.write(to: folder.appendingPathComponent("chapter.tex"), atomically: true, encoding: .utf8)
        let job = try ConversionRequest(source: source, targetFormat: .pdf)
        await queue.submit([job])
        await queue.waitUntilIdle()
        let state = await queue.state(for: job.id)
        if case .succeeded(let pdf) = state {
            guard let contents = PDFDocument(url: pdf)?.string else { fatalError("Unreadable TeX PDF") }
            check(contents.contains("Offline chapter") && contents.contains("See Section 1"), "Offline TeX includes chapter and resolves reference")
            check(try fm.contentsOfDirectory(atPath: folder.path).sorted() == ["Local project.pdf", "Local project.tex", "chapter.tex"], "TeX auxiliary files stay out of project")
            print("PASS: cached offline multi-file LaTeX and cross-references")
        } else if case .failed(let message) = state, message.contains("not found") || message.contains("not cached") {
            print("UNVERIFIED: Tectonic fixture requires a complete local package cache")
        } else {
            fatalError("Tectonic export failed: \(String(describing: state))")
        }
    } else {
        print("SKIP: Tectonic executable unavailable")
    }
    if PandocEngine().availability == .ready {
        let md = folder.appendingPathComponent("Markdown test.md")
        try """
        # Markdown test

        Equation $x^2$ and **emphasis**.

        | Heading | Value |
        | --- | --- |
        | One | Two |

        ```text
        local code block
        ```
        """.write(to: md, atomically: true, encoding: .utf8)
        let jobs = try [FileFormat.html, .docx, .latex].map { try ConversionRequest(source: md, targetFormat: $0) }
        await queue.submit(jobs)
        await queue.waitUntilIdle()
        let states = await queue.states(for: jobs.map(\.id))
        check(states.allSatisfy { if case .succeeded = $0 { true } else { false } }, "Markdown exports: \(states)")
        print("PASS: Pandoc Markdown HTML, DOCX, and TeX exports")
    } else {
        print("SKIP: Pandoc executable unavailable")
    }
}
