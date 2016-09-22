// Copyright 2016 Google Inc. Use of this source code is governed by an
// MIT-style license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:math' as math;

import 'callable.dart';
import 'environment.dart';
import 'exception.dart';
import 'utils.dart';
import 'value.dart';

final _microsoftFilterStart = new RegExp(r'^[a-zA-Z]+\s*=');

final _random = new math.Random();

void defineCoreFunctions(Environment environment) {
  // ## RGB

  environment.defineFunction("rgb", r"$red, $green, $blue", (arguments) {
    // TODO: support calc strings
    var red = arguments[0].assertNumber("red");
    var green = arguments[1].assertNumber("green");
    var blue = arguments[2].assertNumber("blue");

    return new SassColor.rgb(
        fuzzyRound(_percentageOrUnitless(red, 255, "red")),
        fuzzyRound(_percentageOrUnitless(green, 255, "green")),
        fuzzyRound(_percentageOrUnitless(blue, 255, "blue")));
  });

  environment.setFunction(new BuiltInCallable.overloaded("rgba", [
    r"$red, $green, $blue, $alpha",
    r"$color, $alpha",
  ], [
    (arguments) {
      // TODO: support calc strings
      var red = arguments[0].assertNumber("red");
      var green = arguments[1].assertNumber("green");
      var blue = arguments[2].assertNumber("blue");
      var alpha = arguments[3].assertNumber("alpha");

      return new SassColor.rgb(
          _percentageOrUnitless(red, 255, "red").round(),
          _percentageOrUnitless(green, 255, "green").round(),
          _percentageOrUnitless(blue, 255, "blue").round(),
          _percentageOrUnitless(alpha, 1, "alpha"));
    },
    (arguments) {
      var color = arguments[0].assertColor("color");
      var alpha = arguments[0].assertNumber("alpha");
      return color.changeAlpha(_percentageOrUnitless(alpha, 1, "alpha"));
    }
  ]));

  environment.defineFunction("red", r"$color", (arguments) {
    return new SassNumber(arguments.first.assertColor("color").red);
  });

  environment.defineFunction("green", r"$color", (arguments) {
    return new SassNumber(arguments.first.assertColor("color").green);
  });

  environment.defineFunction("blue", r"$color", (arguments) {
    return new SassNumber(arguments.first.assertColor("color").blue);
  });

  environment.defineFunction("mix", r"$color1, $color2, $weight: 50%",
      (arguments) {
    var color1 = arguments[0].assertColor("color1");
    var color2 = arguments[1].assertColor("color2");
    var weight = arguments[2].assertNumber("weight");
    return _mix(color1, color2, weight);
  });

  // ## HSL

  environment.defineFunction("hsl", r"$hue, $saturation, $lightness",
      (arguments) {
    // TODO: support calc strings
    var hue = arguments[0].assertNumber("hue");
    var saturation = arguments[1].assertNumber("saturation");
    var lightness = arguments[2].assertNumber("lightness");

    return new SassColor.hsl(hue.value, saturation.value, lightness.value);
  });

  environment.defineFunction("hsla", r"$hue, $saturation, $lightness, $alpha",
      (arguments) {
    // TODO: support calc strings
    var hue = arguments[0].assertNumber("hue");
    var saturation = arguments[1].assertNumber("saturation");
    var lightness = arguments[2].assertNumber("lightness");
    var alpha = arguments[3].assertNumber("alpha");

    return new SassColor.hsl(hue.value, saturation.value, lightness.value,
        _percentageOrUnitless(alpha, 1, "alpha"));
  });

  environment.defineFunction(
      "hue",
      r"$color",
      (arguments) =>
          new SassNumber(arguments.first.assertColor("color").hue, "deg"));

  environment.defineFunction(
      "saturation",
      r"$color",
      (arguments) =>
          new SassNumber(arguments.first.assertColor("color").saturation, "%"));

  environment.defineFunction(
      "lightness",
      r"$color",
      (arguments) =>
          new SassNumber(arguments.first.assertColor("color").lightness, "%"));

  environment.defineFunction("adjust-hue", r"$color, $degrees", (arguments) {
    var color = arguments[0].assertColor("color");
    var degrees = arguments[1].assertNumber("degrees");
    return color.changeHsl(hue: color.hue + degrees.value);
  });

  environment.defineFunction("lighten", r"$color, $amount", (arguments) {
    var color = arguments[0].assertColor("color");
    var amount = arguments[1].assertNumber("amount");
    return color.changeHsl(
        lightness: color.lightness + amount.valueInRange(0, 100, "amount"));
  });

  environment.defineFunction("darken", r"$color, $amount", (arguments) {
    var color = arguments[0].assertColor("color");
    var amount = arguments[1].assertNumber("amount");
    return color.changeHsl(
        lightness: color.lightness - amount.valueInRange(0, 100, "amount"));
  });

  environment.defineFunction("saturate", r"$color, $amount", (arguments) {
    var color = arguments[0].assertColor("color");
    var amount = arguments[1].assertNumber("amount");
    return color.changeHsl(
        saturation: color.saturation + amount.valueInRange(0, 100, "amount"));
  });

  environment.defineFunction("desaturate", r"$color, $amount", (arguments) {
    var color = arguments[0].assertColor("color");
    var amount = arguments[1].assertNumber("amount");
    return color.changeHsl(
        saturation: color.saturation - amount.valueInRange(0, 100, "amount"));
  });

  environment.defineFunction("grayscale", r"$color", (arguments) {
    if (arguments[0] is SassNumber) {
      return new SassString("grayscale(${arguments[0]})");
    }

    var color = arguments[0].assertColor("color");
    return color.changeHsl(saturation: 0);
  });

  environment.defineFunction("complement", r"$color", (arguments) {
    var color = arguments[0].assertColor("color");
    return color.changeHsl(hue: color.hue + 180);
  });

  environment.defineFunction("invert", r"$color, $weight: 50%", (arguments) {
    if (arguments[0] is SassNumber) {
      // TODO: find some way of ensuring this is stringified using the right
      // options. We may need to resort to zones.
      return new SassString("invert(${arguments[0]})");
    }

    var color = arguments[0].assertColor("color");
    var weight = arguments[1].assertNumber("weight");
    var inverse = color.changeRgb(
        red: 255 - color.red, green: 255 - color.green, blue: 255 - color.blue);
    if (weight.value == 50) return inverse;

    return _mix(color, inverse, weight);
  });

  // ## Opacity

  environment.setFunction(new BuiltInCallable.overloaded("alpha", [
    r"$color",
    r"$args..."
  ], [
    (arguments) {
      var argument = arguments[0];
      if (argument is SassString &&
          !argument.hasQuotes &&
          argument.text.contains(_microsoftFilterStart)) {
        // Suport the proprietary Microsoft alpha() function.
        return new SassString("alpha($argument)");
      }

      var color = argument.assertColor("color");
      return new SassNumber(color.alpha);
    },
    (arguments) {
      if (arguments.every((argument) =>
          argument is SassString &&
          !argument.hasQuotes &&
          argument.text.contains(_microsoftFilterStart))) {
        // Suport the proprietary Microsoft alpha() function.
        return new SassString("alpha(${arguments.join(', ')})");
      }

      assert(arguments.length != 1);
      throw new InternalException(
          "Only 1 argument allowed, but ${arguments.length} were passed.");
    }
  ]));

  environment.defineFunction("opacity", r"$color", (arguments) {
    if (arguments[0] is SassNumber) {
      return new SassString("opacity(${arguments[0]})");
    }

    var color = arguments[0].assertColor("color");
    return new SassNumber(color.alpha);
  });

  environment.defineFunction("opacify", r"$color", _opacify);
  environment.defineFunction("fade-in", r"$color", _opacify);
  environment.defineFunction("transparentize", r"$color", _transparentize);
  environment.defineFunction("fade-out", r"$color", _transparentize);

  // ## Miscellaneous Color

  environment.defineFunction("adjust-color", r"$color, $kwargs...",
      (arguments) {
    var color = arguments[0].assertColor("color");
    var argumentList = arguments[1] as SassArgumentList;
    if (argumentList.contents.isNotEmpty) {
      throw new InternalException(
          "Only only positional argument is allowed. All other arguments must "
          "be passed by name.");
    }

    var keywords = normalizedMap/*<Value>*/()..addAll(argumentList.keywords);
    getInRange(String name, num min, num max) =>
        keywords.remove(name)?.assertNumber(name)?.valueInRange(min, max, name);

    var red = getInRange("red", -255, 255);
    var green = getInRange("green", -255, 255);
    var blue = getInRange("blue", -255, 255);
    var hue = keywords.remove("hue")?.assertNumber("hue")?.value;
    var saturation = getInRange("saturation", -100, 100);
    var lightness = getInRange("lightness", -100, 100);
    var alpha = getInRange("alpha", -1, 1);

    if (keywords.isNotEmpty) {
      throw new InternalException(
          "No ${pluralize('argument', keywords.length)} named "
          "${toSentence(keywords.keys.map((name) => "\$$name"), 'or')}.");
    }

    var hasRgb = red != null || green != null || blue != null;
    var hasHsl = hue != null || saturation != null || lightness != null;
    if (hasRgb) {
      if (hasHsl) {
        throw new InternalException(
            "RGB parameters may not be passed along with HSL parameters.");
      }

      return color.changeRgb(
          red: color.red + (red ?? 0),
          green: color.green + (green ?? 0),
          blue: color.blue + (blue ?? 0),
          alpha: color.alpha + (alpha ?? 0));
    } else if (hasHsl) {
      return color.changeHsl(
          hue: color.hue + (hue ?? 0),
          saturation: color.saturation + (saturation ?? 0),
          lightness: color.lightness + (lightness ?? 0),
          alpha: color.alpha + (alpha ?? 0));
    } else {
      return color.changeAlpha(color.alpha + (alpha ?? 0));
    }
  });

  environment.defineFunction("scale-color", r"$color, $kwargs...", (arguments) {
    var color = arguments[0].assertColor("color");
    var argumentList = arguments[1] as SassArgumentList;
    if (argumentList.contents.isNotEmpty) {
      throw new InternalException(
          "Only only positional argument is allowed. All other arguments must "
          "be passed by name.");
    }

    var keywords = normalizedMap/*<Value>*/()..addAll(argumentList.keywords);
    getScale(String name) {
      var value = keywords.remove(name);
      if (value == null) return null;
      var number = value.assertNumber(name);
      number.assertUnit("%", name);
      return number.valueInRange(-100, 100, name) / 100;
    }

    scaleValue(num current, num scale, num max) {
      if (scale == null) return current;
      return current + (scale > 0 ? max - current : current) * scale;
    }

    var red = getScale("red");
    var green = getScale("green");
    var blue = getScale("blue");
    var saturation = getScale("saturation");
    var lightness = getScale("lightness");
    var alpha = getScale("alpha");

    if (keywords.isNotEmpty) {
      throw new InternalException(
          "No ${pluralize('argument', keywords.length)} named "
          "${toSentence(keywords.keys.map((name) => "\$$name"), 'or')}.");
    }

    var hasRgb = red != null || green != null || blue != null;
    var hasHsl = saturation != null || lightness != null;
    if (hasRgb) {
      if (hasHsl) {
        throw new InternalException(
            "RGB parameters may not be passed along with HSL parameters.");
      }

      return color.changeRgb(
          red: scaleValue(color.red, red, 255),
          green: scaleValue(color.green, green, 255),
          blue: scaleValue(color.blue, blue, 255),
          alpha: scaleValue(color.alpha, alpha, 1));
    } else if (hasHsl) {
      return color.changeHsl(
          saturation: scaleValue(color.saturation, saturation, 100),
          lightness: scaleValue(color.lightness, lightness, 100),
          alpha: scaleValue(color.alpha, alpha, 1));
    } else {
      return color.changeAlpha(scaleValue(color.alpha, alpha, 1));
    }
  });

  environment.defineFunction("change-color", r"$color, $kwargs...",
      (arguments) {
    var color = arguments[0].assertColor("color");
    var argumentList = arguments[1] as SassArgumentList;
    if (argumentList.contents.isNotEmpty) {
      throw new InternalException(
          "Only only positional argument is allowed. All other arguments must "
          "be passed by name.");
    }

    var keywords = normalizedMap/*<Value>*/()..addAll(argumentList.keywords);
    getInRange(String name, num min, num max) =>
        keywords.remove(name)?.assertNumber(name)?.valueInRange(min, max, name);

    var red = getInRange("red", 0, 255);
    var green = getInRange("green", 0, 255);
    var blue = getInRange("blue", 0, 255);
    var hue = keywords.remove("hue")?.assertNumber("hue")?.value;
    var saturation = getInRange("saturation", 0, 100);
    var lightness = getInRange("lightness", 0, 100);
    var alpha = getInRange("alpha", 0, 1);

    if (keywords.isNotEmpty) {
      throw new InternalException(
          "No ${pluralize('argument', keywords.length)} named "
          "${toSentence(keywords.keys.map((name) => "\$$name"), 'or')}.");
    }

    var hasRgb = red != null || green != null || blue != null;
    var hasHsl = saturation != null || lightness != null;
    if (hasRgb) {
      if (hasHsl) {
        throw new InternalException(
            "RGB parameters may not be passed along with HSL parameters.");
      }

      return color.changeRgb(red: red, green: green, blue: blue, alpha: alpha);
    } else if (hasHsl) {
      return color.changeHsl(
          hue: hue, saturation: saturation, lightness: lightness, alpha: alpha);
    } else {
      return color.changeAlpha(alpha);
    }
  });

  environment.defineFunction("ie-hex-str", r"$color", (arguments) {
    var color = arguments[0].assertColor("color");
    hexString(int component) =>
        component.toRadixString(16).padLeft(2, '0').toUpperCase();
    return new SassString(
        "#${hexString(fuzzyRound(color.alpha * 255))}${hexString(color.red)}"
        "${hexString(color.green)}${hexString(color.blue)}");
  });

  // ## String

  environment.defineFunction("unquote", r"$string", (arguments) {
    var string = arguments[0].assertString("string");
    if (!string.hasQuotes) return string;
    return new SassString(string.text);
  });

  environment.defineFunction("quote", r"$string", (arguments) {
    var string = arguments[0].assertString("string");
    if (string.hasQuotes) return string;
    return new SassString(string.text, quotes: true);
  });

  environment.defineFunction("str-length", r"$string", (arguments) {
    var string = arguments[0].assertString("string");
    return new SassNumber(string.text.runes.length);
  });

  environment.defineFunction("str-insert", r"$string, $insert, $index",
      (arguments) {
    var string = arguments[0].assertString("string");
    var insert = arguments[1].assertString("insert");
    var index = arguments[2].assertNumber("index");
    index.assertNoUnits("index");

    var codeUnitIndex = codepointIndexToCodeUnitIndex(string.text,
        _codepointForIndex(index.assertInt("index"), string.text.runes.length));
    return new SassString(
        string.text.replaceRange(codeUnitIndex, codeUnitIndex, insert.text),
        quotes: string.hasQuotes);
  });

  environment.defineFunction("str-index", r"$string, $substring", (arguments) {
    var string = arguments[0].assertString("string");
    var substring = arguments[1].assertString("substring");

    var codeUnitIndex = string.text.indexOf(substring.text);
    if (codeUnitIndex == -1) return sassNull;
    var codePointIndex =
        codeUnitIndexToCodepointIndex(string.text, codeUnitIndex);
    return new SassNumber(codePointIndex + 1);
  });

  environment.defineFunction("str-slice", r"$string, $start-at, $end-at: -1",
      (arguments) {
    var string = arguments[0].assertString("string");
    var start = arguments[1].assertNumber("start-at");
    var end = arguments[2].assertNumber("end-at");
    start.assertNoUnits("start");
    end.assertNoUnits("end");

    var lengthInCodepoints = string.text.runes.length;
    var startCodepoint =
        _codepointForIndex(start.assertInt(), lengthInCodepoints);
    var endCodepoint = _codepointForIndex(end.assertInt(), lengthInCodepoints);
    return new SassString(
        string.text.substring(
            codepointIndexToCodeUnitIndex(string.text, startCodepoint),
            codepointIndexToCodeUnitIndex(string.text, endCodepoint) + 1),
        quotes: string.hasQuotes);
  });

  environment.defineFunction("to-upper-case", r"$string", (arguments) {
    var string = arguments[0].assertString("string");
    return new SassString(string.text.toUpperCase(), quotes: string.hasQuotes);
  });

  environment.defineFunction("to-lower-case", r"$string", (arguments) {
    var string = arguments[0].assertString("string");
    return new SassString(string.text.toLowerCase(), quotes: string.hasQuotes);
  });

  // ## Number

  environment.defineFunction("percentage", r"$number", (arguments) {
    var number = arguments[0].assertNumber("number");
    number.assertNoUnits("number");
    return new SassNumber(number.value * 100, '%');
  });

  environment.setFunction(_numberFunction("round", fuzzyRound));
  environment.setFunction(_numberFunction("ceil", (value) => value.ceil()));
  environment.setFunction(_numberFunction("floor", (value) => value.floor()));
  environment.setFunction(_numberFunction("abs", (value) => value.abs()));

  environment.defineFunction("max", r"$numbers...", (arguments) {
    SassNumber max;
    for (var value in arguments[0].asList) {
      var number = value.assertNumber();
      if (max == null || max.lessThan(number).isTruthy) max = number;
    }
    if (max != null) return max;
    throw new InternalException("At least one argument must be passed.");
  });

  environment.defineFunction("min", r"$numbers...", (arguments) {
    SassNumber min;
    for (var value in arguments[0].asList) {
      var number = value.assertNumber();
      if (min == null || min.greaterThan(number).isTruthy) min = number;
    }
    if (min != null) return min;
    throw new InternalException("At least one argument must be passed.");
  });

  environment.defineFunction("random", r"$limit: null", (arguments) {
    if (arguments[0] == sassNull) return new SassNumber(_random.nextDouble());
    var limit = arguments[0].assertNumber("limit").assertInt("limit");
    if (limit < 1) {
      throw new InternalException(
          "\$limit: Must be greater than 0, was $limit.");
    }
    return new SassNumber(_random.nextInt(limit + 1) + 1);
  });

  // ## List

  environment.defineFunction("length", r"$list",
      (arguments) => new SassNumber(arguments[0].asList.length));

  environment.defineFunction("nth", r"$list, $n", (arguments) {
    var list = arguments[0].asList;
    var index = arguments[1].assertNumber("n");
    return list[index.assertIndexFor(list, "n")];
  });

  environment.defineFunction("set-nth", r"$list, $n, $value", (arguments) {
    var list = arguments[0].asList;
    var index = arguments[1].assertNumber("n");
    var value = arguments[2];
    var newList = list.toList();
    newList[index.assertIndexFor(list, "n")] = value;
    return arguments[0].changeListContents(newList);
  });

  environment.defineFunction(
      "join", r"$list1, $list2, $separator: auto, $bracketed: auto",
      (arguments) {
    var list1 = arguments[0];
    var list2 = arguments[1];
    var separatorParam = arguments[2].assertString("separator");
    var bracketedParam = arguments[3];

    ListSeparator separator;
    if (separatorParam.text == "auto") {
      if (list1.separator != ListSeparator.undecided) {
        separator = list1.separator;
      } else if (list2.separator != ListSeparator.undecided) {
        separator = list2.separator;
      } else {
        separator = ListSeparator.space;
      }
    } else if (separatorParam.text == "space") {
      separator = ListSeparator.space;
    } else if (separatorParam.text == "comma") {
      separator = ListSeparator.comma;
    } else {
      throw new InternalException(
          '\$$separator: Must be "space", "comma", or "auto".');
    }

    var bracketed =
        bracketedParam is SassString && bracketedParam.text == 'auto'
            ? list1.hasBrackets
            : bracketedParam.isTruthy;

    var newList = list1.asList.toList()..addAll(list2.asList);
    return new SassList(newList, separator, brackets: bracketed);
  });

  environment.defineFunction("append", r"$list, $val, $separator: auto",
      (arguments) {
    var list = arguments[0];
    var value = arguments[1];
    var separatorParam = arguments[2].assertString("separator");

    ListSeparator separator;
    if (separatorParam.text == "auto") {
      separator = list.separator == ListSeparator.undecided
          ? ListSeparator.space
          : list.separator;
    } else if (separatorParam.text == "space") {
      separator = ListSeparator.space;
    } else if (separatorParam.text == "comma") {
      separator = ListSeparator.comma;
    } else {
      throw new InternalException(
          '\$$separator: Must be "space", "comma", or "auto".');
    }

    var newList = list.asList.toList()..add(value);
    return list.changeListContents(newList, separator: separator);
  });

  // ## Introspection

  environment.defineFunction("inspect", r"$value",
      (arguments) => new SassString(arguments.first.toString()));
}

num _percentageOrUnitless(SassNumber number, num max, String name) {
  num value;
  if (!number.hasUnits) {
    value = number.value;
  } else if (number.hasUnit("%")) {
    value = max * number.value / 100;
  } else {
    throw new InternalException(
        '\$$name: Expected $number to have no units or "%".');
  }

  return value.clamp(0, max);
}

SassColor _mix(SassColor color1, SassColor color2, SassNumber weight) {
  // This algorithm factors in both the user-provided weight (w) and the
  // difference between the alpha values of the two colors (a) to decide how
  // to perform the weighted average of the two RGB values.
  //
  // It works by first normalizing both parameters to be within [-1, 1], where
  // 1 indicates "only use color1", -1 indicates "only use color2", and all
  // values in between indicated a proportionately weighted average.
  //
  // Once we have the normalized variables w and a, we apply the formula
  // (w + a)/(1 + w*a) to get the combined weight (in [-1, 1]) of color1. This
  // formula has two especially nice properties:
  //
  //   * When either w or a are -1 or 1, the combined weight is also that
  //     number (cases where w * a == -1 are undefined, and handled as a
  //     special case).
  //
  //   * When a is 0, the combined weight is w, and vice versa.
  //
  // Finally, the weight of color1 is renormalized to be within [0, 1] and the
  // weight of color2 is given by 1 minus the weight of color1.
  var weightScale = weight.valueInRange(0, 100, "weight") / 100;
  var normalizedWeight = weightScale * 2 - 1;
  var alphaDistance = color1.alpha - color2.alpha;

  var combinedWeight1 = normalizedWeight * alphaDistance == -1
      ? normalizedWeight
      : (normalizedWeight + alphaDistance) /
          (1 + normalizedWeight * alphaDistance);
  var weight1 = (combinedWeight1 + 1) / 2;
  var weight2 = 1 - weight1;

  return new SassColor.rgb(
      (color1.red * weight1 + color2.red * weight2).round(),
      (color1.green * weight1 + color2.green * weight2).round(),
      (color1.blue * weight1 + color2.blue * weight2).round(),
      color1.alpha * weightScale + color2.alpha * (1 - weightScale));
}

SassColor _opacify(List<Value> arguments) {
  var color = arguments[0].assertColor("color");
  var amount = arguments[1].assertNumber("amount");

  return color.changeAlpha(color.alpha + amount.valueInRange(0, 1, "amount"));
}

SassColor _transparentize(List<Value> arguments) {
  var color = arguments[0].assertColor("color");
  var amount = arguments[1].assertNumber("amount");

  return color.changeAlpha(color.alpha - amount.valueInRange(0, 1, "amount"));
}

int _codepointForIndex(int index, int lengthInCodepoints) {
  if (index == 0) return 0;
  if (index > 0) return math.min(index - 1, lengthInCodepoints);
  return math.max(lengthInCodepoints + index, 0);
}

BuiltInCallable _numberFunction(String name, num transform(num value)) {
  return new BuiltInCallable(name, r"$number", (arguments) {
    var number = arguments[0].assertNumber("number");
    return new SassNumber.withUnits(transform(number.value),
        numeratorUnits: number.numeratorUnits,
        denominatorUnits: number.denominatorUnits);
  });
}
