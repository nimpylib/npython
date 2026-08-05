async def identity(value):
    return await value


assert identity(3) == 3


def async_for_sum(values):
    result = 0
    async for value in values:
        result = result + value
    return result


assert async_for_sum([1, 2, 3]) == 6
