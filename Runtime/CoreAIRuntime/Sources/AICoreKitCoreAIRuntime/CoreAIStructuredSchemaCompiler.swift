import Foundation
import FoundationModels

enum CoreAIStructuredSchemaCompiler {
    static func compile(
        schemaJSON: String,
        name: String,
        description: String?,
        strict: Bool
    ) throws -> GenerationSchema {
        guard
            let data =
                schemaJSON.data(
                    using: .utf8
                )
        else {
            throw RuntimeStructuredSchemaError
                .invalidSchema(
                    "Schema is not UTF-8"
                )
        }

        let raw: Any
        do {
            raw = try JSONSerialization
                .jsonObject(
                    with: data
                )
        } catch {
            throw RuntimeStructuredSchemaError
                .invalidSchema(
                    "Schema is not valid JSON"
                )
        }

        guard
            let root =
                raw as? [String: Any]
        else {
            throw RuntimeStructuredSchemaError
                .invalidSchema(
                    "Schema root must be an object"
                )
        }

        var compiler =
            Compiler(
                rootName: name,
                rootDescription:
                    description,
                strict: strict
            )

        let dynamic =
            try compiler.compile(
                root,
                suggestedName:
                    name,
                depth: 0
            )

        do {
            return try GenerationSchema(
                root: dynamic,
                dependencies: []
            )
        } catch {
            throw RuntimeStructuredSchemaError
                .invalidSchema(
                    "Foundation Models rejected the generation schema"
                )
        }
    }

    private struct Compiler {
        let rootName: String
        let rootDescription: String?
        let strict: Bool
        var nextTypeID = 0

        mutating func compile(
            _ object: [String: Any],
            suggestedName: String,
            depth: Int
        ) throws
            -> DynamicGenerationSchema
        {
            guard depth <= 32 else {
                throw RuntimeStructuredSchemaError
                    .invalidSchema(
                        "Schema nesting is too deep"
                    )
            }

            guard
                let type =
                    object["type"]
                    as? String
            else {
                throw RuntimeStructuredSchemaError
                    .invalidSchema(
                        "Every schema node requires a type"
                    )
            }

            let typeName =
                makeTypeName(
                    suggestedName
                )
            let description =
                try optionalString(
                    object[
                        "description"
                    ],
                    field:
                        "description"
                )

            switch type {
            case "string":
                try rejectUnknownKeys(
                    object,
                    allowed: [
                        "type",
                        "description",
                        "enum"
                    ]
                )

                if let rawEnum =
                    object["enum"]
                {
                    guard
                        let values =
                            rawEnum
                            as? [Any]
                    else {
                        throw RuntimeStructuredSchemaError
                            .invalidSchema(
                                "enum must be an array"
                            )
                    }

                    let choices =
                        values.compactMap {
                            $0 as? String
                        }

                    guard
                        !choices.isEmpty,
                        choices.count
                            == values.count,
                        Set(choices).count
                            == choices.count
                    else {
                        throw RuntimeStructuredSchemaError
                            .invalidSchema(
                                "enum must contain distinct strings"
                            )
                    }

                    return DynamicGenerationSchema(
                        name: typeName,
                        description:
                            description,
                        anyOf:
                            choices
                    )
                }

                return DynamicGenerationSchema(
                    type: String.self
                )

            case "integer":
                try rejectUnknownKeys(
                    object,
                    allowed: [
                        "type",
                        "description",
                        "minimum",
                        "maximum"
                    ]
                )

                let minimum =
                    try optionalInteger(
                        object["minimum"],
                        field: "minimum"
                    )
                let maximum =
                    try optionalInteger(
                        object["maximum"],
                        field: "maximum"
                    )

                return DynamicGenerationSchema(
                    type: Int.self,
                    guides:
                        integerGuides(
                            minimum:
                                minimum,
                            maximum:
                                maximum
                        )
                )

            case "number":
                try rejectUnknownKeys(
                    object,
                    allowed: [
                        "type",
                        "description",
                        "minimum",
                        "maximum"
                    ]
                )

                let minimum =
                    try optionalDouble(
                        object["minimum"],
                        field: "minimum"
                    )
                let maximum =
                    try optionalDouble(
                        object["maximum"],
                        field: "maximum"
                    )

                return DynamicGenerationSchema(
                    type: Double.self,
                    guides:
                        doubleGuides(
                            minimum:
                                minimum,
                            maximum:
                                maximum
                        )
                )

            case "boolean":
                try rejectUnknownKeys(
                    object,
                    allowed: [
                        "type",
                        "description"
                    ]
                )

                return DynamicGenerationSchema(
                    type: Bool.self
                )

            case "array":
                try rejectUnknownKeys(
                    object,
                    allowed: [
                        "type",
                        "description",
                        "items",
                        "minItems",
                        "maxItems"
                    ]
                )

                guard
                    let itemObject =
                        object["items"]
                        as? [String: Any]
                else {
                    throw RuntimeStructuredSchemaError
                        .invalidSchema(
                            "Array schema requires an object items schema"
                        )
                }

                let minimum =
                    try optionalNonnegativeInteger(
                        object["minItems"],
                        field: "minItems"
                    )
                let maximum =
                    try optionalNonnegativeInteger(
                        object["maxItems"],
                        field: "maxItems"
                    )

                if
                    let minimum,
                    let maximum,
                    minimum > maximum
                {
                    throw RuntimeStructuredSchemaError
                        .invalidSchema(
                            "minItems exceeds maxItems"
                        )
                }

                let itemSchema =
                    try compile(
                        itemObject,
                        suggestedName:
                            typeName
                            + "_item",
                        depth:
                            depth + 1
                    )

                return DynamicGenerationSchema(
                    arrayOf:
                        itemSchema,
                    minimumElements:
                        minimum,
                    maximumElements:
                        maximum
                )

            case "object":
                try rejectUnknownKeys(
                    object,
                    allowed: [
                        "type",
                        "description",
                        "properties",
                        "required",
                        "additionalProperties"
                    ]
                )

                if
                    let additional =
                        object[
                            "additionalProperties"
                        ],
                    let value =
                        additional as? Bool,
                    value
                {
                    throw RuntimeStructuredSchemaError
                        .invalidSchema(
                            "additionalProperties: true is not supported"
                        )
                }

                if strict,
                   object[
                    "additionalProperties"
                   ] != nil
                {
                    guard
                        let value =
                            object[
                                "additionalProperties"
                            ]
                            as? Bool,
                        value == false
                    else {
                        throw RuntimeStructuredSchemaError
                            .invalidSchema(
                                "Strict object schemas require additionalProperties: false"
                            )
                    }
                }

                let properties =
                    object[
                        "properties"
                    ] as? [String: Any]
                    ?? [:]

                let required =
                    try requiredNames(
                        object[
                            "required"
                        ],
                        properties:
                            properties
                    )
                let requiredSet =
                    Set(required)

                let remaining =
                    properties.keys
                    .filter {
                        !requiredSet
                            .contains($0)
                    }
                    .sorted()
                let orderedNames =
                    required
                    + remaining

                let dynamicProperties =
                    try orderedNames.map {
                        propertyName
                        -> DynamicGenerationSchema.Property
                        in

                        guard
                            let child =
                                properties[
                                    propertyName
                                ]
                                as? [String: Any]
                        else {
                            throw RuntimeStructuredSchemaError
                                .invalidSchema(
                                    "Property "
                                    + propertyName
                                    + " must be an object schema"
                                )
                        }

                        let childDescription =
                            try optionalString(
                                child[
                                    "description"
                                ],
                                field:
                                    "description"
                            )
                        let childSchema =
                            try compile(
                                child,
                                suggestedName:
                                    typeName
                                    + "_"
                                    + propertyName,
                                depth:
                                    depth + 1
                            )

                        return DynamicGenerationSchema
                            .Property(
                                name:
                                    propertyName,
                                description:
                                    childDescription,
                                schema:
                                    childSchema,
                                isOptional:
                                    !requiredSet
                                    .contains(
                                        propertyName
                                    )
                            )
                    }

                return DynamicGenerationSchema(
                    name:
                        depth == 0
                        ? rootName
                        : typeName,
                    description:
                        depth == 0
                        ? (
                            rootDescription
                            ?? description
                        )
                        : description,
                    properties:
                        dynamicProperties
                )

            default:
                throw RuntimeStructuredSchemaError
                    .invalidSchema(
                        "Unsupported schema type: "
                        + type
                    )
            }
        }

        mutating func makeTypeName(
            _ suggestedName: String
        ) -> String {
            let normalized =
                suggestedName
                .filter {
                    $0.isLetter
                    || $0.isNumber
                    || $0 == "_"
                }

            let base =
                normalized.isEmpty
                ? rootName
                : normalized
            let value =
                base
                + "_"
                + String(
                    nextTypeID
                )
            nextTypeID += 1
            return value
        }

        func requiredNames(
            _ value: Any?,
            properties: [String: Any]
        ) throws -> [String] {
            guard let value else {
                return []
            }

            guard
                let values =
                    value as? [Any]
            else {
                throw RuntimeStructuredSchemaError
                    .invalidSchema(
                        "required must be an array"
                    )
            }

            let names =
                values.compactMap {
                    $0 as? String
                }

            guard
                names.count
                    == values.count,
                Set(names).count
                    == names.count
            else {
                throw RuntimeStructuredSchemaError
                    .invalidSchema(
                        "required must contain distinct strings"
                    )
            }

            for name in names {
                guard
                    properties[
                        name
                    ] != nil
                else {
                    throw RuntimeStructuredSchemaError
                        .invalidSchema(
                            "required references undeclared property "
                            + name
                        )
                }
            }

            return names
        }

        func rejectUnknownKeys(
            _ object: [String: Any],
            allowed: Set<String>
        ) throws {
            let unknown =
                Set(object.keys)
                .subtracting(
                    allowed
                )

            guard unknown.isEmpty else {
                throw RuntimeStructuredSchemaError
                    .invalidSchema(
                        "Unsupported schema keywords: "
                        + unknown
                        .sorted()
                        .joined(
                            separator: ", "
                        )
                    )
            }
        }

        func optionalString(
            _ value: Any?,
            field: String
        ) throws -> String? {
            guard let value else {
                return nil
            }

            guard
                let string =
                    value as? String
            else {
                throw RuntimeStructuredSchemaError
                    .invalidSchema(
                        field
                        + " must be a string"
                    )
            }

            return string
        }

        func optionalDouble(
            _ value: Any?,
            field: String
        ) throws -> Double? {
            guard let value else {
                return nil
            }

            guard
                let number =
                    value as? NSNumber
            else {
                throw RuntimeStructuredSchemaError
                    .invalidSchema(
                        field
                        + " must be a number"
                    )
            }

            let result =
                number.doubleValue

            guard result.isFinite else {
                throw RuntimeStructuredSchemaError
                    .invalidSchema(
                        field
                        + " must be finite"
                    )
            }

            return result
        }

        func optionalInteger(
            _ value: Any?,
            field: String
        ) throws -> Int? {
            guard
                let number =
                    try optionalDouble(
                        value,
                        field: field
                    )
            else {
                return nil
            }

            guard
                number.rounded()
                    == number,
                number
                    >= Double(Int.min),
                number
                    <= Double(Int.max)
            else {
                throw RuntimeStructuredSchemaError
                    .invalidSchema(
                        field
                        + " must be an integer"
                    )
            }

            return Int(number)
        }

        func optionalNonnegativeInteger(
            _ value: Any?,
            field: String
        ) throws -> Int? {
            guard
                let result =
                    try optionalInteger(
                        value,
                        field: field
                    )
            else {
                return nil
            }

            guard result >= 0 else {
                throw RuntimeStructuredSchemaError
                    .invalidSchema(
                        field
                        + " must be nonnegative"
                    )
            }

            return result
        }

        func integerGuides(
            minimum: Int?,
            maximum: Int?
        ) -> [GenerationGuide<Int>] {
            switch (
                minimum,
                maximum
            ) {
            case let (
                lower?,
                upper?
            ):
                return [
                    .range(
                        lower...upper
                    )
                ]
            case let (
                lower?,
                nil
            ):
                return [
                    .minimum(
                        lower
                    )
                ]
            case let (
                nil,
                upper?
            ):
                return [
                    .maximum(
                        upper
                    )
                ]
            case (
                nil,
                nil
            ):
                return []
            }
        }

        func doubleGuides(
            minimum: Double?,
            maximum: Double?
        ) -> [GenerationGuide<Double>] {
            switch (
                minimum,
                maximum
            ) {
            case let (
                lower?,
                upper?
            ):
                return [
                    .range(
                        lower...upper
                    )
                ]
            case let (
                lower?,
                nil
            ):
                return [
                    .minimum(
                        lower
                    )
                ]
            case let (
                nil,
                upper?
            ):
                return [
                    .maximum(
                        upper
                    )
                ]
            case (
                nil,
                nil
            ):
                return []
            }
        }
    }
}

enum RuntimeStructuredSchemaError:
    Error
{
    case invalidSchema(String)
}
