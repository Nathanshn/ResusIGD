import XCTest
@testable import ClinicalCore

final class ClinicalFormatTests: XCTestCase {
    func testIndonesianSeparators() {
        XCTAssertEqual(ClinicalFormat.number(1234.5, maxDecimals: 1), "1.234,5")
        XCTAssertEqual(ClinicalFormat.number(1234567), "1.234.567")
        XCTAssertEqual(ClinicalFormat.number(0.125, maxDecimals: 2), "0,13")
        XCTAssertEqual(ClinicalFormat.number(5.0, maxDecimals: 2), "5")
        XCTAssertEqual(ClinicalFormat.number(5.0, maxDecimals: 2, minDecimals: 1), "5,0")
        XCTAssertEqual(ClinicalFormat.number(-2.5, maxDecimals: 1), "-2,5")
        XCTAssertEqual(ClinicalFormat.number(-0.001, maxDecimals: 1), "0")
        XCTAssertEqual(ClinicalFormat.number(.nan), "–")
        XCTAssertEqual(ClinicalFormat.rate(5.25), "5,3")
        XCTAssertEqual(ClinicalFormat.volume(0.75), "0,75")
        XCTAssertEqual(ClinicalFormat.volume(6.25), "6,3")
        XCTAssertEqual(ClinicalFormat.dose(0.016), "0,016")
        XCTAssertEqual(ClinicalFormat.drops(233.33), "233")
        XCTAssertEqual(ClinicalFormat.drops(1.75), "1,8")
    }

    func testParseAcceptsCommaAndDot() {
        XCTAssertEqual(ClinicalFormat.parse("12,5"), 12.5)
        XCTAssertEqual(ClinicalFormat.parse("12.5"), 12.5)
        XCTAssertEqual(ClinicalFormat.parse(" 70 "), 70)
        XCTAssertEqual(ClinicalFormat.parse("1.234,5"), 1234.5)
        XCTAssertNil(ClinicalFormat.parse(""))
        XCTAssertNil(ClinicalFormat.parse("abc"))
        XCTAssertNil(ClinicalFormat.parse("inf"))
    }
}

final class FuzzySearchTests: XCTestCase {
    private var guidelines: [Guideline] { Fixtures.seed.guidelines }

    func testExactAndKeywordMatches() {
        XCTAssertEqual(FuzzySearch.searchGuidelines(guidelines, query: "stemi").first?.id, "sindrom-koroner-akut")
        XCTAssertEqual(FuzzySearch.searchGuidelines(guidelines, query: "parkland").first?.id, "luka-bakar")
        XCTAssertEqual(FuzzySearch.searchGuidelines(guidelines, query: "kejang").first?.id, "status-epileptikus")
    }

    func testTyposDiacriticsAndGluedWords() {
        XCTAssertEqual(FuzzySearch.searchGuidelines(guidelines, query: "anafilaxis").first?.id, "anafilaksis")
        XCTAssertEqual(FuzzySearch.searchGuidelines(guidelines, query: "lukabakar").first?.id, "luka-bakar")
        XCTAssertEqual(FuzzySearch.searchGuidelines(guidelines, query: "STROKE").first?.id, "code-stroke")
        XCTAssertEqual(FuzzySearch.searchGuidelines(guidelines, query: "hiponatrmia").first?.id, "koreksi-elektrolit")
    }

    func testNoMatchAndEmptyQuery() {
        XCTAssertTrue(FuzzySearch.searchGuidelines(guidelines, query: "xyzqw").isEmpty)
        XCTAssertEqual(FuzzySearch.searchGuidelines(guidelines, query: "  ").count, guidelines.count)
    }

    func testPediatricDrugSearch() {
        XCTAssertEqual(FuzzySearch.searchPediatricDrugs(Fixtures.seed.pediatricDrugs, query: "parasetamol").first?.id, "paracetamol")
        XCTAssertEqual(FuzzySearch.searchPediatricDrugs(Fixtures.seed.pediatricDrugs, query: "ceftriaxone").first?.id, "ceftriaxone")
    }

    func testEditDistance() {
        XCTAssertEqual(FuzzySearch.editDistance("kitten", "sitting"), 3)
        XCTAssertEqual(FuzzySearch.editDistance("", "abc"), 3)
    }
}

final class ResusSessionEngineTests: XCTestCase {
    /// 17/11/2026 07:00:00 UTC
    let t0 = Date(timeIntervalSince1970: 1_794_898_800)

    func testCPRCycleCountdown() {
        var s = ResusSessionEngine(mode: .cardiacArrest, startedAt: t0)
        XCTAssertNil(s.cprCycleRemaining(at: t0))
        s.log(.cprStart, label: "RJP Dimulai", at: t0.addingTimeInterval(10))
        XCTAssertEqual(s.cprCycleRemaining(at: t0.addingTimeInterval(40)) ?? 0, 90, accuracy: accuracy)
        XCTAssertEqual(s.cprCycleRemaining(at: t0.addingTimeInterval(140)) ?? 0, 110, accuracy: accuracy, "new cycle after 120 s")
        XCTAssertEqual(s.completedCycles(at: t0.addingTimeInterval(250)), 2)
        s.log(.rhythmCheck, label: "Cek Irama", at: t0.addingTimeInterval(100))
        XCTAssertEqual(s.cprCycleRemaining(at: t0.addingTimeInterval(100)) ?? 0, 120, accuracy: accuracy, "rhythm check restarts cycle")
        s.log(.rosc, label: "ROSC", at: t0.addingTimeInterval(300))
        XCTAssertNil(s.cprCycleRemaining(at: t0.addingTimeInterval(310)))
    }

    func testEpinephrineReminder() {
        var s = ResusSessionEngine(mode: .cardiacArrest, startedAt: t0, epinephrineInterval: 240)
        XCTAssertNil(s.epinephrineDueIn(at: t0))
        s.log(.epinephrine, label: "Epinefrin 1 mg IV", at: t0.addingTimeInterval(60))
        XCTAssertEqual(s.epinephrineDueIn(at: t0.addingTimeInterval(100)) ?? 0, 200, accuracy: accuracy)
        XCTAssertEqual(s.epinephrineDueIn(at: t0.addingTimeInterval(400)) ?? 0, -100, accuracy: accuracy)
        s.log(.epinephrine, label: "Epinefrin 1 mg IV", at: t0.addingTimeInterval(320))
        XCTAssertEqual(s.count(of: .epinephrine), 2)
        XCTAssertEqual(s.epinephrineDueIn(at: t0.addingTimeInterval(400)) ?? 0, 160, accuracy: accuracy)
    }

    func testSeizurePhases() {
        let s = ResusSessionEngine(mode: .statusEpilepticus, startedAt: t0)
        XCTAssertEqual(s.seizurePhase(at: t0.addingTimeInterval(60)), .stabilization)
        XCTAssertEqual(s.seizurePhase(at: t0.addingTimeInterval(5 * 60)), .initialTherapy)
        XCTAssertEqual(s.seizurePhase(at: t0.addingTimeInterval(21 * 60)), .secondTherapy)
        XCTAssertEqual(s.seizurePhase(at: t0.addingTimeInterval(45 * 60)), .refractory)
        XCTAssertEqual(s.secondsToNextSeizurePhase(at: t0.addingTimeInterval(4 * 60)) ?? 0, 60, accuracy: accuracy)
        XCTAssertNil(s.secondsToNextSeizurePhase(at: t0.addingTimeInterval(50 * 60)))
    }

    func testSeizureOnsetCanPrecedeSessionStart() {
        var s = ResusSessionEngine(mode: .statusEpilepticus, startedAt: t0)
        s.log(.note, label: "Kejang Dimulai (onset)", at: t0.addingTimeInterval(-10 * 60))
        XCTAssertEqual(s.seizurePhase(at: t0), .initialTherapy)
        XCTAssertEqual(s.events.first?.label, "Kejang Dimulai (onset)", "events stay chronological")
    }

    func testUndoLastIntervention_restoresCycleAnchor() {
        var s = ResusSessionEngine(mode: .cardiacArrest, startedAt: t0)
        s.log(.cprStart, label: "RJP Dimulai", at: t0.addingTimeInterval(10))
        s.log(.rosc, label: "ROSC", at: t0.addingTimeInterval(200))
        XCTAssertNil(s.cycleStartedAt)
        XCTAssertEqual(s.undoLastIntervention()?.kind, .rosc)
        XCTAssertEqual(s.cycleStartedAt, t0.addingTimeInterval(10), "undoing ROSC resumes the CPR cycle")
        XCTAssertEqual(s.undoLastIntervention()?.kind, .cprStart)
        XCTAssertNil(s.undoLastIntervention(), "session start marker is never removed")
        XCTAssertEqual(s.events.count, 1)
    }

    func testCodableRoundTrip() throws {
        var s = ResusSessionEngine(mode: .cardiacArrest, startedAt: t0, epinephrineInterval: 180)
        s.log(.epinephrine, label: "Epinefrin 1 mg IV", at: t0.addingTimeInterval(30))
        let decoded = try JSONDecoder().decode(ResusSessionEngine.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded, s)
    }

    func testEndingSessionFreezesElapsed() {
        var s = ResusSessionEngine(mode: .cardiacArrest, startedAt: t0)
        s.end(at: t0.addingTimeInterval(600))
        s.end(at: t0.addingTimeInterval(900))
        XCTAssertEqual(s.elapsed(at: t0.addingTimeInterval(5000)), 600, accuracy: accuracy)
        XCTAssertEqual(s.count(of: .sessionEnd), 1)
    }

    func testClockFormat() {
        XCTAssertEqual(ResusSessionEngine.clock(65), "01:05")
        XCTAssertEqual(ResusSessionEngine.clock(3725), "1:02:05")
        XCTAssertEqual(ResusSessionEngine.clock(-100), "-01:40")
    }

    func testSOAPFormatter_cardiacArrest() {
        var s = ResusSessionEngine(mode: .cardiacArrest, startedAt: t0)
        s.log(.cprStart, label: "RJP Dimulai", at: t0.addingTimeInterval(5))
        s.log(.defibrillation, label: "Defibrilasi 200J", at: t0.addingTimeInterval(130))
        s.log(.epinephrine, label: "Epinefrin 1 mg IV", at: t0.addingTimeInterval(250))
        s.log(.rosc, label: "ROSC", at: t0.addingTimeInterval(1080))
        let text = SOAPLogFormatter.format(session: s, now: t0.addingTimeInterval(1200), timeZone: TimeZone(identifier: "UTC")!, patientInfo: "Tn. X, 55 thn")

        XCTAssertTrue(text.contains("Tanggal 17/11/2026 · Mulai 07:00:00"))
        XCTAssertTrue(text.contains("Pasien: Tn. X, 55 thn"))
        XCTAssertTrue(text.contains("- [07:00:05] (+00:05) RJP Dimulai"))
        XCTAssertTrue(text.contains("- [07:02:10] (+02:10) Defibrilasi 200J"))
        XCTAssertTrue(text.contains("Epinefrin: 1×. Defibrilasi: 1×."))
        XCTAssertTrue(text.contains("ROSC tercapai pukul 07:18:00 (+18:00"))
        XCTAssertTrue(text.contains("Perawatan pasca-ROSC"))
        let s1 = text.range(of: "S:")!.lowerBound, o = text.range(of: "O:")!.lowerBound
        let a = text.range(of: "\nA:")!.lowerBound, p = text.range(of: "\nP:")!.lowerBound
        XCTAssertTrue(s1 < o && o < a && a < p, "SOAP order")
    }

    func testSOAPFormatter_statusEpilepticusWithoutEvents() {
        let s = ResusSessionEngine(mode: .statusEpilepticus, startedAt: t0)
        let text = SOAPLogFormatter.format(session: s, now: t0.addingTimeInterval(25 * 60), timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertTrue(text.contains("(belum ada tindakan tercatat)"))
        XCTAssertTrue(text.contains("20–40 menit"))
    }
}

final class SeedDataTests: XCTestCase {
    func testSeedLoadsAndHasRequiredContent() {
        let seed = Fixtures.seed
        let adultIDs = Set(seed.adultDrugs.map(\.id))
        XCTAssertTrue(adultIDs.isSuperset(of: ["norepinefrin", "dopamin", "dobutamin", "epinefrin", "sulfas-atropin", "amiodaron", "nicardipin", "nitrogliserin"]))
        let pediatricIDs = Set(seed.pediatricDrugs.map(\.id))
        XCTAssertTrue(pediatricIDs.isSuperset(of: ["diazepam", "fenitoin", "fenobarbital", "midazolam", "paracetamol", "ibuprofen", "ketorolac", "metamizole", "ondansetron", "domperidone", "ampisilin", "gentamisin", "cefotaxime", "ceftriaxone", "amoxicillin", "azithromycin", "epinefrin-anak", "dexamethasone", "salbutamol"]))
        let guidelineIDs = Set(seed.guidelines.map(\.id))
        XCTAssertTrue(guidelineIDs.isSuperset(of: ["code-stroke", "luka-bakar", "acls-henti-jantung", "acls-bradikardia", "acls-takikardia", "atls-primary-survey", "atls-syok-hemoragik", "status-epileptikus", "anafilaksis", "sindrom-koroner-akut"]))
        XCTAssertEqual(seed.versionSignature, "a1-p1-g1")
    }

    func testSeedPassesValidator() {
        XCTAssertEqual(SeedValidator.validate(Fixtures.seed), [])
    }

    func testValidatorCatchesBrokenData() {
        var drug = Fixtures.adult("dopamin")
        drug.regimens[0].defaultDose = 50
        drug.diluentRules.removeLast()
        let problems = SeedValidator.validateAdult([drug, drug])
        XCTAssertTrue(problems.contains { $0.contains("duplicate") })
        XCTAssertTrue(problems.contains { $0.contains("min ≤ default ≤ max") })
        XCTAssertTrue(problems.contains { $0.contains("missing diluent rule") })

        var child = Fixtures.pediatric("paracetamol")
        child.regimens[0].formulationIDs.append("ghost")
        child.regimens[0].maxSingleDoseMg = nil
        let pediatricProblems = SeedValidator.validatePediatric([child])
        XCTAssertTrue(pediatricProblems.contains { $0.contains("unknown formulation ghost") })
        XCTAssertTrue(pediatricProblems.contains { $0.contains("adult cap") })
    }

    func testEveryAdultRegimenComputesAtDefaults() {
        for drug in Fixtures.seed.adultDrugs {
            for regimen in drug.regimens {
                switch regimen.mode {
                case .infusion:
                    let r = InfusionCalculator.calculate(drug: drug, regimen: regimen, weightKg: 70, dose: regimen.defaultDose,
                                                         preparation: InfusionPreparation.defaults(for: drug))
                    XCTAssertTrue(r.isValid, "\(drug.id)/\(regimen.id)")
                    XCTAssertGreaterThan(r.rateMLPerHour, 0, "\(drug.id)/\(regimen.id)")
                case .bolus:
                    let r = InfusionCalculator.bolus(drug: drug, regimen: regimen, doseMg: regimen.defaultDose, ampoule: drug.ampoule)
                    XCTAssertTrue(r.isValid, "\(drug.id)/\(regimen.id)")
                }
            }
        }
    }

    func testEveryPediatricRegimenHasAUsableFormulationFor20kgChild() {
        for drug in Fixtures.seed.pediatricDrugs {
            for regimen in drug.regimens {
                let results = drug.formulations(for: regimen).map {
                    PediatricDoseCalculator.calculate(drug: drug, regimen: regimen, formulation: $0, weightKg: 20, ageMonths: 72)
                }
                XCTAssertTrue(results.contains { $0.isValid }, "\(drug.id)/\(regimen.id)")
                for result in results where result.isValid {
                    if let cap = regimen.maxSingleDoseMg {
                        XCTAssertLessThanOrEqual(result.doseMg, cap + 1e-9, "\(drug.id)/\(regimen.id)")
                    }
                }
            }
        }
    }
}
