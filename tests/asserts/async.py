async def identity(value):
    return value


assert asyncio.run(identity(3)) == 3


async def nested(value):
    return await identity(value)


assert asyncio.run(nested(4)) == 4


def async_for_sum(values):
    result = 0
    async for value in values:
        result = result + value
    return result


assert async_for_sum([1, 2, 3]) == 6
