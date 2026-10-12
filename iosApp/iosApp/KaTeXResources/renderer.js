"use strict";

window.renderFormula = async function(request) {
  const output = document.getElementById("formula");
  output.replaceChildren();
  output.style.fontSize = request.pointSize + "px";
  output.style.color = request.color;
  output.style.paddingRight = request.isBlockLayout ? "0.35em" : "0.15em";
  output.setAttribute("aria-label", request.accessibilityLabel);

  try {
    katex.render(request.latex, output, {
      displayMode: request.displayMode,
      throwOnError: true,
      strict: "ignore",
      trust: false,
      maxExpand: 1000,
      maxSize: 100,
      output: "htmlAndMathml"
    });
    await document.fonts.ready;
    const rect = output.getBoundingClientRect();
    const measuredWidth = Math.max(rect.width, output.scrollWidth);
    const widthSafety = request.isBlockLayout ? 4 : 1;
    return {
      ok: true,
      width: Math.ceil(measuredWidth) + widthSafety,
      height: Math.ceil(rect.height)
    };
  } catch (error) {
    output.replaceChildren();
    return {
      ok: false,
      error: String(error && error.message ? error.message : error)
    };
  }
};
