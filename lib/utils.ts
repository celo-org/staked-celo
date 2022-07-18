
// Parse a comma delimited string to an array.
export const parseArray = (arrString: string | undefined) =>
    arrString ? arrString.split(",") : [];
